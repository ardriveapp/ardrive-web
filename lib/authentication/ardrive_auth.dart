import 'dart:async';
import 'dart:convert';

import 'package:ardrive/arns/data/arns_pending_action_store.dart';
import 'package:ardrive/arns/data/arns_wallet_store.dart';
import 'package:ardrive/locked_drives/domain/drive_unlock_session.dart';
import 'package:ardrive/locked_drives/domain/drive_unlocker.dart';
import 'package:ardrive/permanence/permanence_cache.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/models/database/database_helpers.dart';
import 'package:ardrive/services/arconnect/arconnect.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/authentication/biometric_authentication.dart';
import 'package:ardrive/user/repositories/user_repository.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/constants.dart';
import 'package:ardrive/utils/graphql_retry.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/metadata_cache.dart';
import 'package:ardrive/utils/secure_key_value_store.dart';
import 'package:ardrive_logger/ardrive_logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:stash_shared_preferences/stash_shared_preferences.dart';

import '../core/crypto/crypto.dart';

abstract class ArDriveAuth {
  Future<bool> isUserLoggedIn();
  Future<bool> isExistingUser(Wallet wallet);
  Future<bool> userHasPassword(Wallet wallet);
  Future<User> login(
    Wallet wallet,
    String password,
    ProfileType profileType, {
    String? sourceWalletAddress,
  });
  Future<User> unlockWithBiometrics({required String localizedReason});
  Future<User> unlockUser({required String password});
  Future<void> logout();
  User get currentUser;
  Stream<User?> onAuthStateChanged();
  Future<bool> isBiometricsEnabled();
  Future<String?> getWalletAddress();
  String getJWTAsString();
  Future<void> refreshBalance();

  factory ArDriveAuth({
    required ArweaveService arweave,
    required UserRepository userRepository,
    required ArDriveCrypto crypto,
    required BiometricAuthentication biometricAuthentication,
    required SecureKeyValueStore secureKeyValueStore,
    required ArConnectService arConnectService,
    required DatabaseHelpers databaseHelpers,
    MetadataCache? metadataCache,
    ArNSWalletStore? arnsWalletStore,
    ArNSPendingActionStore? arnsPendingActionStore,
    DriveUnlocker? driveUnlocker,
  }) =>
      ArDriveAuthImpl(
        driveUnlocker: driveUnlocker,
        arweave: arweave,
        userRepository: userRepository,
        crypto: crypto,
        databaseHelpers: databaseHelpers,
        biometricAuthentication: biometricAuthentication,
        secureKeyValueStore: secureKeyValueStore,
        arConnectService: arConnectService,
        metadataCache: metadataCache,
        arnsWalletStore: arnsWalletStore,
        arnsPendingActionStore: arnsPendingActionStore,
      );
}

class ArDriveAuthImpl implements ArDriveAuth {
  ArDriveAuthImpl({
    required ArweaveService arweave,
    required UserRepository userRepository,
    required ArDriveCrypto crypto,
    required BiometricAuthentication biometricAuthentication,
    required SecureKeyValueStore secureKeyValueStore,
    required ArConnectService arConnectService,
    required DatabaseHelpers databaseHelpers,
    MetadataCache? metadataCache,
    PermanenceCache? permanenceCache,
    ArNSWalletStore? arnsWalletStore,
    ArNSPendingActionStore? arnsPendingActionStore,
    DriveUnlocker? driveUnlocker,
  })  : _arweave = arweave,
        _injectedDriveUnlocker = driveUnlocker,
        _crypto = crypto,
        _databaseHelpers = databaseHelpers,
        _arConnectService = arConnectService,
        _secureKeyValueStore = secureKeyValueStore,
        _biometricAuthentication = biometricAuthentication,
        _userRepository = userRepository,
        _maybeMetadataCache = metadataCache,
        _permanenceCache = permanenceCache ?? PermanenceCache.shared,
        _arnsWalletStore = arnsWalletStore ?? ArNSWalletStore(),
        _arnsPendingActionStore =
            arnsPendingActionStore ?? ArNSPendingActionStore();

  final UserRepository _userRepository;
  final ArweaveService _arweave;

  final DriveUnlocker? _injectedDriveUnlocker;

  /// Tries the sign-in password on the wallet's private drives. The app
  /// passes its shared one, whose session drive discovery uses too, so a
  /// drive the sign-in opened is not signed for again straight after.
  late final DriveUnlocker _driveUnlocker = _injectedDriveUnlocker ??
      DriveUnlocker(
        crypto: _crypto,
        arweave: _arweave,
        driveDao: _databaseHelpers.driveDao,
        session: DriveUnlockSession(),
      );
  final ArDriveCrypto _crypto;
  final BiometricAuthentication _biometricAuthentication;
  final SecureKeyValueStore _secureKeyValueStore;
  final ArConnectService _arConnectService;
  final DatabaseHelpers _databaseHelpers;
  MetadataCache? _maybeMetadataCache;

  /// What the permanence panel last read for this wallet.
  final PermanenceCache _permanenceCache;

  /// The ArNS wallet linked to each profile, forgotten at sign-out.
  final ArNSWalletStore _arnsWalletStore;

  /// Each profile's unfinished Turbo ArNS actions, forgotten at sign-out.
  final ArNSPendingActionStore _arnsPendingActionStore;

  User? _currentUser;

  // getters and setters
  @override
  User get currentUser {
    if (_currentUser == null) {
      throw const AuthenticationUserIsNotLoggedInException();
    }

    return _currentUser!;
  }

  @visibleForTesting
  set currentUser(User? user) {
    _currentUser = user;
  }

  @override
  Stream<User?> onAuthStateChanged() => _userStreamController.stream;

  Future<MetadataCache> get _metadataCache async {
    _maybeMetadataCache ??= await MetadataCache.fromCacheStore(
      await newSharedPreferencesCacheStore(),
    );
    return _maybeMetadataCache!;
  }

  final StreamController<User?> _userStreamController =
      StreamController<User?>.broadcast();

  @override
  Future<bool> isUserLoggedIn() async {
    return await _userRepository.hasUser();
  }

  @override
  Future<bool> isExistingUser(Wallet wallet) async {
    try {
      final driveTxs = await _arweave.getUniqueUserDriveEntityTxs(
        await wallet.getAddress(),
        maxRetries: profileQueryMaxRetries,
      );

      return driveTxs.isNotEmpty;
    } catch (e) {
      if (e is GraphQLException) {
        throw const AuthenticationGatewayException();
      }

      rethrow;
    }
  }

  /// To have at least a single private drive means the user has set a password.
  @override
  Future<bool> userHasPassword(Wallet wallet) async {
    try {
      final firstDrivePrivateDriveTx = await _getFirstPrivateDriveTx(wallet);

      return firstDrivePrivateDriveTx != null;
    } catch (e) {
      if (e is GraphQLException) {
        throw const AuthenticationGatewayException();
      }

      rethrow;
    }
  }

  @override
  Future<User> login(
    Wallet wallet,
    String password,
    ProfileType profileType, {
    String? sourceWalletAddress,
  }) async {
    try {
      await _validateUser(wallet, password);

      if (await _biometricAuthentication.isEnabled()) {
        logger.i('Saving password in secure storage');

        _savePasswordInSecureStorage(password);
      }

      currentUser = await _addUser(
        wallet,
        password,
        profileType,
        sourceWalletAddress: sourceWalletAddress,
      );

      _userStreamController.add(_currentUser);

      return currentUser;
    } catch (e) {
      if (e is GraphQLException) {
        throw const AuthenticationGatewayException();
      }

      rethrow;
    }
  }

  @override
  Future<User> unlockUser({required String password}) async {
    try {
      logger.d('Unlocking user with password');

      currentUser = await _userRepository.getUser(password);

      unawaited(_updateBalance());

      if (await _biometricAuthentication.isEnabled()) {
        logger.i('Saving password in secure storage');

        _savePasswordInSecureStorage(password);
      }

      logger.d('User unlocked with password');

      _userStreamController.add(_currentUser);

      return currentUser;
    } catch (e) {
      if (e is ProfilePasswordIncorrectException) {
        throw WrongPasswordException('Incorrect password.');
      }

      logger.e(
        'Failed to unlock user with password. The password is wrong or a network error occurred',
        e,
        StackTrace.current,
      );

      rethrow;
    }
  }

  @override
  Future<User> unlockWithBiometrics({
    required String localizedReason,
  }) async {
    logger.d('Unlocking with biometrics');

    if (await isUserLoggedIn()) {
      final isAuthenticated = await _biometricAuthentication.authenticate(
        localizedReason: localizedReason,
        useCached: true,
      );

      logger.d('Biometric authentication result: $isAuthenticated');

      if (isAuthenticated) {
        logger.i('User is logged in. Unlocking with password');
        // load from local storage
        final storedPassword = await _secureKeyValueStore.getString('password');

        if (storedPassword == null) {
          throw AuthenticationUnknownException(
            'Biometric authentication failed. Password not found',
          );
        }

        return await unlockUser(password: storedPassword);
      }
    }

    throw WrongPasswordException('Biometric authentication failed');
  }

  @override
  Future<void> logout() async {
    logger.i('Logging out user');

    try {
      await _userRepository.deleteUser();

      if (_currentUser != null) {
        await _disconnectFromArConnect();
        (await _metadataCache).clear();
        await _secureKeyValueStore.remove('password');
        await _secureKeyValueStore.remove('biometricEnabled');
      }

      await _databaseHelpers.deleteAllTables();
      await _databaseHelpers.clearSessionMemory();
      // Locked drives, wallet signatures and proven passwords: memory only,
      // and none of it may outlive the session.
      _injectedDriveUnlocker?.session.clear();
      await _permanenceCache.clear();
      await _arnsWalletStore.clear();
      await _arnsPendingActionStore.clear();
      currentUser = null;
      _userStreamController.add(null);
    } catch (e, stacktrace) {
      logger.e('Failed to logout user', e, stacktrace);
      throw AuthenticationUnknownException('Failed to logout user');
    }
  }

  Future<void> _disconnectFromArConnect() async {
    final isExtensionAvailable = _arConnectService.isExtensionPresent();
    if (isExtensionAvailable) {
      final hasArConnectPermissions =
          await _arConnectService.checkPermissions();
      if (hasArConnectPermissions) {
        try {
          await _arConnectService.disconnect();
        } catch (e, stacktrace) {
          logger.e('Failed to disconnect from ArConnect', e, stacktrace);
        }
      }
    }
  }

  @override
  Future<bool> isBiometricsEnabled() {
    return _biometricAuthentication.isEnabled();
  }

  /// Checks the sign-in password against the wallet's private drives.
  ///
  /// The rule: the password is accepted if it opens **any** private drive
  /// this wallet owns, or if the wallet owns none. Drives it doesn't open are
  /// not an error - they show as locked, each with its own Unlock.
  ///
  /// Why not "must open the first private drive", as it was: drives can have
  /// different passwords (the CLI, desktop and core-js make them), and a
  /// wallet whose first drive used another password could never sign in.
  ///
  /// Why not "accept anything": the password still guards this device's
  /// profile and is tried on every drive, so a typo must not be taken as a
  /// password that opens nothing. If the wallet has private drives and this
  /// password opens none of them, it is still "Wrong password".
  ///
  /// Only an AES-GCM authentication failure counts against the password. A
  /// drive that can't be read leaves the question open: if no drive opened
  /// and one couldn't be read, the sign-in reports the gateway, not "Wrong
  /// password". A wallet prompt that is cancelled ends the check
  /// as "Wrong password", as it always has.
  Future<void> _validateUser(
    Wallet wallet,
    String password,
  ) async {
    final privateDriveTxs = (await _arweave.getUniqueUserDriveEntityTxs(
      await wallet.getAddress(),
      maxRetries: profileQueryMaxRetries,
    ))
        .where((tx) =>
            tx.getTag(EntityTag.drivePrivacy) == DrivePrivacyTag.private)
        .toList();

    if (privateDriveTxs.isEmpty) {
      return;
    }

    Object? unreadable;

    for (final driveTx in privateDriveTxs) {
      final Uint8List data;

      try {
        // Login, not a user-initiated fetch: read the configured gateway
        // rather than walking the GAR waterfall behind a spinner.
        data = await _arweave.getEntityDataBytes(
          driveTx.id,
          configuredGatewayOnly: true,
        );
      } catch (e) {
        logger.w('Could not read a private drive to check the password: $e');
        unreadable ??= e;
        continue;
      }

      final attempt = await _driveUnlocker.tryPassword(
        wallet: wallet,
        driveTx: driveTx,
        data: data,
        password: password,
      );

      switch (attempt.failure) {
        case null:
          return;
        case DriveUnlockFailure.wrongPassword:
          continue;
        case DriveUnlockFailure.walletDeclined:
          throw WrongPasswordException('Password is incorrect');
        case DriveUnlockFailure.unavailable:
          unreadable ??= const AuthenticationGatewayException();
          continue;
      }
    }

    if (unreadable is TransactionNotFound) {
      throw const PrivateDriveNotFoundException();
    }

    if (unreadable != null) {
      throw const AuthenticationGatewayException();
    }

    throw WrongPasswordException('Password is incorrect');
  }

  Future<User> _addUser(
    Wallet wallet,
    String password,
    ProfileType profileType, {
    String? sourceWalletAddress,
  }) async {
    await _saveUser(password, profileType, wallet,
        sourceWalletAddress: sourceWalletAddress);

    currentUser = await _userRepository.getUser(password);

    unawaited(_updateBalance());

    _userStreamController.add(_currentUser);

    return currentUser;
  }

  /// Fetches the balance and publishes the updated user through
  /// [onAuthStateChanged]. Login runs this in the background, which is how a
  /// balance that fell back to zero at login gets its real value. Never throws:
  /// on error the previous balance is kept.
  Future<void> _updateBalance() async {
    final user = currentUser;

    try {
      final balance = await _userRepository.getBalance(user.wallet);

      // The user may have logged out, or another wallet logged in, while the
      // request was in flight.
      final latest = _currentUser;
      if (latest == null || latest.walletAddress != user.walletAddress) {
        return;
      }

      _currentUser = latest.copyWith(walletBalance: balance);
      _userStreamController.add(_currentUser);
    } catch (e) {
      logger.e('Error fetching wallet balance', e);
      // Don't update balance on error - keep previous value
    }
  }

  Future<void> _saveUser(
    String password,
    ProfileType profileType,
    Wallet wallet, {
    String? sourceWalletAddress,
  }) async {
    // delete previous user
    // verify if it is necessary, the user only will add a new user if he is not logged in
    if (await _userRepository.hasUser()) {
      await _userRepository.deleteUser();
    }

    // save user
    await _userRepository.saveUser(
      password,
      profileType,
      wallet,
      sourceWalletAddress: sourceWalletAddress,
    );
  }

  Future<void> _savePasswordInSecureStorage(String password) async {
    // save password
    await _secureKeyValueStore.putString('password', password);
  }

  Future<TransactionCommonMixin?> _getFirstPrivateDriveTx(Wallet wallet) async {
    return _arweave.getFirstPrivateDriveTx(
      wallet,
      maxRetries: profileQueryMaxRetries,
    );
  }

  @override
  Future<String?> getWalletAddress() async {
    final owner = await _userRepository.getOwnerOfDefaultProfile();
    if (owner == null) {
      return null;
    }
    return ownerToAddress(owner);
  }

  @override
  String getJWTAsString() {
    if (_currentUser == null) {
      throw const AuthenticationUserIsNotLoggedInException();
    }

    return json.encode(_currentUser!.wallet.toJwk());
  }

  /// Completes once the refreshed balance is in [currentUser], so a caller
  /// can read it straight after.
  @override
  Future<void> refreshBalance() => _updateBalance();
}

class AuthenticationGatewayException implements Exception {
  const AuthenticationGatewayException();
}

class WrongPasswordException implements UntrackedException {
  final String message;

  WrongPasswordException(this.message);

  @override
  String toString() => 'WrongPasswordException: $message';
}

class WalletMismatchException implements UntrackedException {
  const WalletMismatchException();
}

class ArConnectVersionNotSupportedException implements UntrackedException {
  const ArConnectVersionNotSupportedException();
}

class AuthenticationUnknownException implements Exception {
  final String message;

  AuthenticationUnknownException(this.message);
}

class PrivateDriveNotFoundException implements Exception {
  const PrivateDriveNotFoundException();
}

class AuthenticationUserIsNotLoggedInException implements UntrackedException {
  const AuthenticationUserIsNotLoggedInException();
}
