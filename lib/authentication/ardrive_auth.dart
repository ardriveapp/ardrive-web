import 'dart:async';
import 'dart:convert';

import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/database/database_helpers.dart';
import 'package:ardrive/services/arconnect/arconnect.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/authentication/biometric_authentication.dart';
import 'package:ardrive/user/repositories/user_repository.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/constants.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/metadata_cache.dart';
import 'package:ardrive/utils/secure_key_value_store.dart';
import 'package:ardrive_logger/ardrive_logger.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:stash_shared_preferences/stash_shared_preferences.dart';

import '../core/crypto/crypto.dart';

abstract class ArDriveAuth {
  Future<bool> isUserLoggedIn();
  Future<bool> isExistingUser(Wallet wallet);
  Future<bool> userHasPassword(Wallet wallet);
  Future<User> login(Wallet wallet, String password, ProfileType profileType);
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
  }) =>
      ArDriveAuthImpl(
        arweave: arweave,
        userRepository: userRepository,
        crypto: crypto,
        databaseHelpers: databaseHelpers,
        biometricAuthentication: biometricAuthentication,
        secureKeyValueStore: secureKeyValueStore,
        arConnectService: arConnectService,
        metadataCache: metadataCache,
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
  })  : _arweave = arweave,
        _crypto = crypto,
        _databaseHelpers = databaseHelpers,
        _arConnectService = arConnectService,
        _secureKeyValueStore = secureKeyValueStore,
        _biometricAuthentication = biometricAuthentication,
        _userRepository = userRepository,
        _maybeMetadataCache = metadataCache;

  final UserRepository _userRepository;
  final ArweaveService _arweave;
  final ArDriveCrypto _crypto;
  final BiometricAuthentication _biometricAuthentication;
  final SecureKeyValueStore _secureKeyValueStore;
  final ArConnectService _arConnectService;
  final DatabaseHelpers _databaseHelpers;
  MetadataCache? _maybeMetadataCache;

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
    final driveTxs = await _arweave.getUniqueUserDriveEntityTxs(
      await wallet.getAddress(),
      maxRetries: profileQueryMaxRetries,
    );

    return driveTxs.isNotEmpty;
  }

  /// To have at least a single private drive means the user has set a password.
  @override
  Future<bool> userHasPassword(Wallet wallet) async {
    final firstDrivePrivateDriveTxId = await _getFirstPrivateDriveTxId(wallet);

    return firstDrivePrivateDriveTxId != null;
  }

  @override
  Future<User> login(
      Wallet wallet, String password, ProfileType profileType) async {
    final isValidPassword = await _validateUser(
      wallet,
      password,
    );

    if (!isValidPassword) {
      throw AuthenticationFailedException('Incorrect password');
    }

    if (await _biometricAuthentication.isEnabled()) {
      logger.i('Saving password in secure storage');

      _savePasswordInSecureStorage(password);
    }

    currentUser = await _addUser(wallet, password, profileType);

    _userStreamController.add(_currentUser);

    return currentUser;
  }

  @override
  Future<User> unlockUser({required String password}) async {
    try {
      logger.d('Unlocking user with password');

      currentUser = await _userRepository.getUser(password);

      _updateBalance();

      if (await _biometricAuthentication.isEnabled()) {
        logger.i('Saving password in secure storage');

        _savePasswordInSecureStorage(password);
      }

      logger.d('User unlocked with password');

      _userStreamController.add(_currentUser);

      return currentUser;
    } catch (e) {
      logger.e(
        'Failed to unlock user with password. The password is wrong or a network error occurred',
        e,
      );
      // TODO: Improve error handling. There's a PR: https://github.com/ardriveapp/ardrive-web/pull/1243
      throw AuthenticationFailedException('Incorrect password.');
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

    throw AuthenticationFailedException('Biometric authentication failed');
  }

  @override
  Future<void> logout() async {
    logger.d('Logging out user');

    try {
      await _userRepository.deleteUser();

      if (_currentUser != null) {
        await _disconnectFromArConnect();
        (await _metadataCache).clear();
        await _secureKeyValueStore.remove('password');
        await _secureKeyValueStore.remove('biometricEnabled');
      }

      await _databaseHelpers.deleteAllTables();
      currentUser = null;
      _userStreamController.add(null);
    } catch (e, stacktrace) {
      logger.e('Failed to logout user', e, stacktrace);
      throw AuthenticationFailedException('Failed to logout user');
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

  Future<bool> _validateUser(
    Wallet wallet,
    String password,
  ) async {
    final firstDrivePrivateDriveTxId = await _getFirstPrivateDriveTxId(wallet);

    // Try and decrypt one of the user's private drive entities to check if they are entering the
    // right password.
    if (firstDrivePrivateDriveTxId != null) {
      late SecretKey checkDriveKey;
      try {
        checkDriveKey = await _crypto.deriveDriveKey(
          wallet,
          firstDrivePrivateDriveTxId,
          password,
        );
      } catch (e) {
        throw AuthenticationFailedException('Password is incorrect');
      }

      final privateDrive = await _arweave.getLatestDriveEntityWithId(
        firstDrivePrivateDriveTxId,
        driveKey: checkDriveKey,
        driveOwner: await wallet.getAddress(),
        maxRetries: profileQueryMaxRetries,
      );

      return privateDrive != null;
    }

    return true;
  }

  Future<User> _addUser(
    Wallet wallet,
    String password,
    ProfileType profileType,
  ) async {
    await _saveUser(password, profileType, wallet);

    currentUser = await _userRepository.getUser(password);

    _updateBalance();

    _userStreamController.add(_currentUser);

    return currentUser;
  }

  void _updateBalance() {
    _userRepository.getARIOTokens(currentUser.wallet).then((value) {
      _currentUser = _currentUser!.copyWith(
        ioTokens: value,
        errorFetchingIOTokens: false,
      );
      _userStreamController.add(_currentUser);
    }).catchError((e) {
      _currentUser = _currentUser!.copyWith(
        errorFetchingIOTokens: true,
      );
      _userStreamController.add(_currentUser);
      logger.e('Error fetching ARIOTokens', e);
      return Future.value(null);
    });
    _userRepository.getBalance(currentUser.wallet).then((value) {
      _currentUser = _currentUser!.copyWith(walletBalance: value);
      _userStreamController.add(_currentUser);
    });
  }

  Future<void> _saveUser(
    String password,
    ProfileType profileType,
    Wallet wallet,
  ) async {
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
    );
  }

  Future<void> _savePasswordInSecureStorage(String password) async {
    // save password
    await _secureKeyValueStore.putString('password', password);
  }

  Future<String?> _getFirstPrivateDriveTxId(Wallet wallet) async {
    return _arweave.getFirstPrivateDriveTxId(
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

  @override
  Future<void> refreshBalance() async {
    _currentUser = _currentUser!.copyWith(
      errorFetchingIOTokens: false,
    );

    _userStreamController.add(_currentUser);

    _updateBalance();
  }
}

class AuthenticationFailedException implements UntrackedException {
  final String message;

  AuthenticationFailedException(this.message);

  @override
  String toString() => message;
}

class WalletMismatchException implements UntrackedException {
  const WalletMismatchException();
}

class AuthenticationUnknownException implements Exception {
  final String message;

  AuthenticationUnknownException(this.message);
}

class AuthenticationUserIsNotLoggedInException implements UntrackedException {
  const AuthenticationUserIsNotLoggedInException();
}
