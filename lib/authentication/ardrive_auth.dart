import 'dart:async';
import 'dart:convert';

import 'package:ardrive/arns/data/arns_pending_action_store.dart';
import 'package:ardrive/arns/data/arns_wallet_store.dart';
import 'package:ardrive/locked_drives/data/sign_in_password_proof_store.dart';
import 'package:ardrive/locked_drives/domain/drive_password_order.dart';
import 'package:ardrive/locked_drives/domain/drive_unlock_session.dart';
import 'package:ardrive/locked_drives/domain/drive_unlocker.dart';
import 'package:ardrive/permanence/permanence_cache.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/models/database/database_helpers.dart';
import 'package:ardrive/services/arconnect/arconnect.dart';
import 'package:ardrive/services/arconnect/arconnect_prompt.dart';
import 'package:ardrive/services/arconnect/arconnect_wallet.dart';
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

  /// Signs in with [wallet], keeping its profile on this device encrypted
  /// with [password].
  ///
  /// The password is first tried on the wallet's private drives, to open
  /// them: see [ArDriveAuthImpl.validateUser]. If it opens none of
  /// them this throws [PasswordOpensNoDriveException], so the user can
  /// correct it; [skipDriveCheck] signs in anyway, with those drives locked.
  Future<User> login(
    Wallet wallet,
    String password,
    ProfileType profileType, {
    String? sourceWalletAddress,
    bool skipDriveCheck = false,
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
    SignInPasswordProofStore? signInPasswordProofStore,
  }) =>
      ArDriveAuthImpl(
        driveUnlocker: driveUnlocker,
        signInPasswordProofStore: signInPasswordProofStore,
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
    SignInPasswordProofStore? signInPasswordProofStore,
  })  : _arweave = arweave,
        _injectedDriveUnlocker = driveUnlocker,
        _proofStore = signInPasswordProofStore ?? SignInPasswordProofStore(),
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

  /// Whether this device's sign-in password for a wallet was left unproven,
  /// across reloads. See [SignInPasswordProofStore].
  final SignInPasswordProofStore _proofStore;

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
    bool skipDriveCheck = false,
  }) async {
    try {
      if (!skipDriveCheck) {
        await _validateUser(wallet, password);
      }

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

      // Welcome back and biometrics unlock the profile without trying any
      // drive. If the password was left unproven on an earlier visit, the
      // session must know before the drive list is read: discovery spends no
      // wallet prompts on it, and Create drive asks for the drive password.
      if (await _proofStore.isUnproven(currentUser.walletAddress)) {
        _driveUnlocker.session
            .setSignInPasswordProven(currentUser.walletAddress, false);
      }

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
        await _proofStore.clear(_currentUser!.walletAddress);
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

  /// How long signing out waits for each of Wander's answers: a short wait,
  /// since nothing here needs one.
  @visibleForTesting
  static Duration wanderLogoutWait = const Duration(seconds: 3);

  /// Best effort, and never waits on Wander: signing out must finish, and
  /// clear this device, even when Wander is locked or its prompt was closed.
  Future<void> _disconnectFromArConnect() async {
    try {
      if (!_arConnectService.isExtensionPresent()) return;

      final hasArConnectPermissions = await ArConnectPrompt.ask(
        _arConnectService,
        _arConnectService.checkPermissions,
        within: wanderLogoutWait,
        askPerson: false,
      );
      if (hasArConnectPermissions) {
        await ArConnectPrompt.ask(
          _arConnectService,
          _arConnectService.disconnect,
          within: wanderLogoutWait,
          askPerson: false,
        );
      }
    } catch (e, stacktrace) {
      logger.e('Failed to disconnect from ArConnect', e, stacktrace);
    }
  }

  @override
  Future<bool> isBiometricsEnabled() {
    return _biometricAuthentication.isEnabled();
  }

  /// Tries the sign-in password on the wallet's private drives, to open them
  /// for the session. An auto-unlock attempt, not a check of the password:
  /// drive passwords and the sign-in password are separate (the 3.0 password
  /// design), and this password's own job is to encrypt the profile on this
  /// device.
  ///
  /// - The wallet has no private drives: nothing to try; sign in.
  /// - The password opens any of them: sign in; the drives it opens are open.
  /// - It opens none of those tried, or the wallet's prompt is cancelled:
  ///   [PasswordOpensNoDriveException]. The sign-in asks the user to try
  ///   again or continue; continuing signs in with those drives locked, each
  ///   with its own Unlock. Sign-in is never blocked by this.
  /// - A drive couldn't be read and none opened: the gateway is reported, not
  ///   the password.
  ///
  /// Bounded: at most [signInMaxDrives] drives and [signInTimeBudget], and a
  /// wallet that prompts is asked at most [signInMaxNewPrompts] times, oldest
  /// drive first after the drives whose signature is already held.
  ///
  /// Only an AES-GCM authentication failure counts against the password.
  ///
  /// The seam for P3 (sign in without a password): for a browser wallet this
  /// whole step, and the dialog the sign-in shows for its exception, go away.
  /// MetaMask's own password check, which picks the wallet, is elsewhere
  /// (`LoginBloc`) and is identity, not this.
  @visibleForTesting
  Future<void> validateUser(Wallet wallet, String password) =>
      _validateUser(wallet, password);

  /// The most new wallet prompts one sign-in may cost a wallet that asks the
  /// user for each signature (Wander). The drive check at sign-in used to
  /// cost one; a typo must not cost one per private drive.
  static const signInMaxNewPrompts = 3;

  /// The most private drives one sign-in tries, whatever the wallet.
  static const signInMaxDrives = 20;

  /// How long one sign-in spends trying drives before it gives its answer.
  static const signInTimeBudget = Duration(seconds: 20);

  Future<void> _validateUser(
    Wallet wallet,
    String password,
  ) async {
    final address = await wallet.getAddress();
    final privateDriveTxs = (await _arweave.getUniqueUserDriveEntityTxs(
      address,
      maxRetries: profileQueryMaxRetries,
    ))
        .where((tx) =>
            tx.getTag(EntityTag.drivePrivacy) == DrivePrivacyTag.private)
        .toList();

    final session = _driveUnlocker.session;

    if (privateDriveTxs.isEmpty) {
      await _markSignInPassword(address, proven: true);
      return;
    }

    // Which drives, in what order: those whose signature this session already
    // holds first, since trying them asks the wallet nothing; then the rest,
    // oldest first, the drive most likely made with the account's password.
    // A wallet that prompts gets at most [signInMaxNewPrompts] of the rest.
    final createdAt = _arweave.cachedUserDriveCreationTimes(address);
    DateTime created(TransactionCommonMixin tx) {
      final known = createdAt[tx.getTag(EntityTag.driveId)];
      if (known != null) return known;
      try {
        return tx.getCommitTime();
      } catch (_) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
    }

    bool held(TransactionCommonMixin tx) =>
        session.holdsSignatureFor(address, tx.getTag(EntityTag.driveId)!);
    // Drives made before 3.0 by an app that used one password for all of
    // them first, then oldest first. See [drivePasswordTryRank].
    int likeliestFirst(TransactionCommonMixin a, TransactionCommonMixin b) =>
        compareForPasswordTries(a, b, created);

    final heldTxs = privateDriveTxs.where(held).toList()..sort(likeliestFirst);
    final rest = privateDriveTxs.where((tx) => !held(tx)).toList()
      ..sort(likeliestFirst);
    final prompts = wallet is ArConnectWallet;
    final promptBudget =
        prompts ? WalletPromptBudget(signInMaxNewPrompts) : null;

    // A Wander that batch-signs is asked once for every private drive, so
    // the password is tried on up to [signInMaxDrives] of them for that one
    // approval. Otherwise each drive not held is a prompt of its own.
    final batches = wallet is ArConnectWallet &&
        wallet.canBatchSign &&
        !session.batchSigningUnusable(address) &&
        rest.length > 1;

    final candidates = [
      ...heldTxs,
      ...(prompts && !batches ? rest.take(signInMaxNewPrompts) : rest),
    ].take(signInMaxDrives).toList();

    // Their metadata, a few at a time rather than one after another.
    final data = List<Uint8List?>.filled(candidates.length, null);
    final readErrors = List<Object?>.filled(candidates.length, null);

    await ArweaveService.runPooled(
      concurrency: 6,
      itemCount: candidates.length,
      task: (i) async {
        try {
          // Login, not a user-initiated fetch: read the configured gateway
          // rather than walking the GAR waterfall behind a spinner.
          data[i] = await _arweave.getEntityDataBytes(
            candidates[i].id,
            configuredGatewayOnly: true,
          );
        } catch (e) {
          readErrors[i] = e;
        }
      },
    );

    if (batches) {
      final batch = await _driveUnlocker.signInOneApproval(
        wallet: wallet,
        driveIds: [
          for (final tx in [...rest, ...heldTxs]) tx.getTag(EntityTag.driveId)!,
        ],
        password: password,
        proofDrives: [
          for (var i = 0; i < candidates.length; i++)
            if (data[i] != null) (tx: candidates[i], data: data[i]!),
        ],
        promptBudget: promptBudget,
      );

      if (batch == DriveSignatureBatch.declined) {
        // The user said no to their wallet: one no for every drive.
        await _markSignInPassword(address, proven: false);
        throw const PasswordOpensNoDriveException();
      }
    }

    final deadline = DateTime.now().add(signInTimeBudget);
    Object? unreadable;

    for (var i = 0; i < candidates.length; i++) {
      if (DateTime.now().isAfter(deadline)) {
        logger.w('Stopped trying drives at sign-in: out of time');
        break;
      }

      final driveData = data[i];

      if (driveData == null) {
        logger.w('Could not read a private drive to check the password: '
            '${readErrors[i]}');
        unreadable ??= readErrors[i];
        continue;
      }

      // Out of prompts, as when a batch couldn't be used: drives whose
      // signature isn't held are left for discovery and Unlock.
      final outOfPrompts = promptBudget != null && promptBudget.remaining == 0;
      if (outOfPrompts && !held(candidates[i])) continue;

      final attempt = await _driveUnlocker.tryPassword(
        wallet: wallet,
        driveTx: candidates[i],
        data: driveData,
        password: password,
        promptBudget: promptBudget,
      );

      switch (attempt.failure) {
        case null:
          await _markSignInPassword(address, proven: true);
          return;
        case DriveUnlockFailure.wrongPassword:
          continue;
        case DriveUnlockFailure.walletDeclined when outOfPrompts:
          // Not the user: the budget (a v1 drive whose own signature isn't
          // held).
          continue;
        case DriveUnlockFailure.walletDeclined:
        case DriveUnlockFailure.walletFailed:
          // The user said no to their wallet: stop asking it.
          await _markSignInPassword(address, proven: false);
          throw const PasswordOpensNoDriveException();
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

    await _markSignInPassword(address, proven: false);
    throw const PasswordOpensNoDriveException();
  }

  /// Records whether the sign-in password opened a drive: in the session,
  /// and - when it didn't - on this device, so a later visit that only
  /// unlocks the profile still knows. Recorded at the check rather than at
  /// Continue: Try again with the right password records the opposite.
  Future<void> _markSignInPassword(String address,
      {required bool proven}) async {
    _driveUnlocker.session.setSignInPasswordProven(address, proven);

    if (proven) {
      await _proofStore.clear(address);
    } else {
      await _proofStore.markUnproven(address);
    }
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

/// The sign-in password opened none of the private drives it was tried on.
/// Not a wrong password: sign-in may continue, with those drives locked.
class PasswordOpensNoDriveException implements UntrackedException {
  const PasswordOpensNoDriveException();
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
