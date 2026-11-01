import 'dart:async';
import 'dart:convert';

import 'package:ardrive/turbo/utils/get_signature_headers_for_turbo.dart';
import 'package:ardrive/arns/data/arns_pending_action_store.dart';
import 'package:ardrive/arns/data/arns_wallet_store.dart';
import 'package:ardrive/device_unlock/data/device_tabs.dart';
import 'package:ardrive/device_unlock/domain/device_key.dart';
import 'package:ardrive/device_unlock/domain/device_secret_source.dart';
import 'package:ardrive/device_unlock/domain/device_unlocker.dart';
import 'package:ardrive/entities/drive_signature_type.dart';
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

  /// Signs in with a browser wallet (Wander, Phantom, Solflare, MetaMask)
  /// with no ArDrive password: the profile is kept on this device under a
  /// device key from [source], the wallet's one approval.
  ///
  /// No drive is tried: private drives open from the keys this device
  /// remembers, or with Unlock. [password] is only for an existing MetaMask
  /// account, whose password picks its wallet and is its drive password:
  /// it is tried on the private drives first, as [login] does, and kept for
  /// this session only.
  ///
  /// A profile of the same account saved before 3.0 is locked by a password
  /// this sign-in doesn't have, so the drive keys it remembered are dropped,
  /// and those drives start locked.
  ///
  /// Throws [DeviceUnlockRefusedException] when the wallet doesn't give the
  /// device key; nothing is saved then.
  Future<User> loginWithWallet(
    Wallet wallet,
    ProfileType profileType,
    DeviceSecretSource source, {
    String? sourceWalletAddress,
    String password = '',
    bool skipDriveCheck = false,
  });

  /// Opens the account saved on this device with its wallet's one approval
  /// ([source]), for a profile saved by [loginWithWallet]. Throws
  /// [DeviceUnlockRefusedException] when the wallet says no or signs
  /// differently than before; nothing is opened then.
  Future<User> unlockWithWallet(DeviceSecretSource source);

  /// The account saved on this device, for Welcome back; null when none.
  Future<SavedAccount?> savedAccount();

  /// Signs out and clears this device of the account: the profile, every
  /// remembered drive key, and the copies older builds left. Unless
  /// [fromAnotherTab], the other ArDrive tabs are told to sign out too.
  Future<void> logout({bool fromAnotherTab = false});
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
    DeviceTabs? deviceTabs,
    SignInPasswordProofStore? signInPasswordProofStore,
    DeviceUnlocker? deviceUnlocker,
  }) =>
      ArDriveAuthImpl(
        deviceUnlocker: deviceUnlocker,
        deviceTabs: deviceTabs,
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
    DeviceTabs? deviceTabs,
    SignInPasswordProofStore? signInPasswordProofStore,
    DeviceUnlocker? deviceUnlocker,
  })  : _arweave = arweave,
        _deviceUnlocker = deviceUnlocker ?? DeviceUnlocker(),
        _deviceTabs = deviceTabs ?? DeviceTabs.instance,
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

  /// The other ArDrive tabs, told when this one signs out.
  final DeviceTabs _deviceTabs;

  /// The session's device key for an account a browser wallet opens: asked
  /// of the wallet once per sign-in or reload.
  final DeviceUnlocker _deviceUnlocker;

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

      // A new profile on a device an older build used: its copies go too.
      _clearOlderCopiesInBackground();

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

      await _startSession();
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
  Future<User> loginWithWallet(
    Wallet wallet,
    ProfileType profileType,
    DeviceSecretSource source, {
    String? sourceWalletAddress,
    String password = '',
    bool skipDriveCheck = false,
  }) async {
    assert(source.method != DeviceUnlockMethod.password);
    try {
      final address = await wallet.getAddress();

      // Another account on this device: what the session holds in memory
      // goes now, so nothing of it is mixed into this sign-in. Nothing saved
      // goes until the wallet and the checks below have answered: a "no"
      // must not cost the account that is here.
      final previous = await _userRepository.getSavedProfile();
      final switching = previous != null && previous.id != address;
      if (switching) await _clearSessionState();

      if (password.isNotEmpty && !skipDriveCheck) {
        await _validateUser(wallet, password);
      }

      final deviceSalt = newDeviceSalt();
      Uint8List? keyCheck;

      // A new sign-in: whatever an earlier attempt in this tab was told is
      // not this one's answer.
      _deviceUnlocker.clear();
      final outcome = await _deviceUnlocker.unlockToRemember(
        record: DeviceRecord(method: source.method, deviceSalt: deviceSalt),
        source: source,
        saveKeyCheck: (check) async => keyCheck = check,
      );
      final deviceKey = outcome.key;
      if (deviceKey == null || keyCheck == null) {
        throw DeviceUnlockRefusedException(outcome.status);
      }

      if (switching) await _forgetSwitchedAccount(previous.id, source);
      await _replaceSavedProfile(address);
      await _userRepository.saveUserWithDeviceKey(
        wallet: wallet,
        profileType: profileType,
        record: DeviceRecord(
          method: source.method,
          deviceSalt: deviceSalt,
          keyCheck: keyCheck,
        ),
        deviceKey: deviceKey,
        sourceWalletAddress: sourceWalletAddress,
      );

      currentUser = await _userRepository.getUserWithDeviceKey(
        deviceKey,
        password: password,
      );
      await _startSession();
      unawaited(_updateBalance());
      _userStreamController.add(_currentUser);

      return currentUser;
    } catch (e) {
      if (e is GraphQLException) {
        throw const AuthenticationGatewayException();
      }

      rethrow;
    }
  }

  /// Before a browser wallet's profile is saved: the profile already here
  /// goes. If it is this account's, saved before 3.0 under its password, the
  /// drive keys it remembered were wrapped by that password, which this
  /// sign-in doesn't have, so they go too and those drives start locked:
  /// their password opens them again.
  Future<void> _replaceSavedProfile(String address) async {
    final saved = await _userRepository.getSavedProfile();
    if (saved == null) return;
    if (saved.id == address) {
      final dropped = await _databaseHelpers.driveDao
          .discardStoredDriveKeys(ownerAddress: address);
      if (dropped.own + dropped.shared > 0) {
        logger.i('Dropped drive keys remembered under the old password: '
            '${dropped.own} own drives start locked, ${dropped.shared} '
            'shared drives need their link again');
      }
    }
    await _userRepository.deleteUser();
  }

  @override
  Future<User> unlockWithWallet(DeviceSecretSource source) async {
    final record = await _userRepository.getDeviceRecord();
    if (record == null || record.method != source.method) {
      throw const DeviceUnlockRefusedException(DeviceUnlockStatus.failed);
    }

    // Each press of Continue asks again: a "no" a moment ago is not this
    // one's answer.
    _deviceUnlocker.clear();
    final outcome = await _deviceUnlocker.unlockToRead(
      record: record,
      source: source,
      // The profile itself needs the key, remembered drives or not.
      hasRemembered: () async => true,
    );
    final deviceKey = outcome.key;
    if (deviceKey == null) {
      throw DeviceUnlockRefusedException(outcome.status);
    }

    try {
      currentUser = await _userRepository.getUserWithDeviceKey(deviceKey);
    } on DeviceKeyMismatchException {
      _deviceUnlocker.clear();
      throw const DeviceUnlockRefusedException(DeviceUnlockStatus.mismatch);
    }

    await _startSession();
    unawaited(_updateBalance());
    _userStreamController.add(_currentUser);

    return currentUser;
  }

  @override
  Future<SavedAccount?> savedAccount() async {
    final profile = await _userRepository.getSavedProfile();
    if (profile == null) return null;
    return SavedAccount(
      address: profile.id,
      profileType: ProfileType.values[profile.profileType],
      unlockMethod: profile.formatVersion == 1
          ? DeviceUnlockMethod.password
          : DeviceUnlockMethod.fromValue(profile.unlockMethod),
      sourceWalletAddress: profile.sourceWalletAddress,
      publicKey: profile.walletPublicKey,
    );
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

  /// Drives an earlier session kept for itself only ("Remember on this
  /// device" off, or forgotten) still have a row with no key. They go, so
  /// they show as locked. Never stops a sign-in.
  Future<void> _startSession() async {
    _clearOlderCopiesInBackground();
    try {
      final detached = await _databaseHelpers.driveDao.detachForgottenDrives();
      if (detached.isNotEmpty) {
        logger.i('${detached.length} drives not remembered on this device '
            'start locked');
      }
    } catch (e, stackTrace) {
      logger.e('Could not clear drives not remembered here', e, stackTrace);
    }
  }

  /// Every copy of the profile in the format before 3.0 goes, once: see
  /// [DatabaseHelpers.clearOlderCopies]. Not awaited: the `VACUUM` it ends
  /// with can take a moment on a large database, and signing in need not
  /// wait for it.
  void _clearOlderCopiesInBackground() {
    try {
      unawaited(_databaseHelpers.clearOlderCopies());
    } catch (e) {
      logger.w('Could not start clearing older copies: ${e.runtimeType}');
    }
  }

  @override
  Future<void> logout({bool fromAnotherTab = false}) async {
    // Signed Turbo headers belong to the account that signed them.
    TurboSignatureHeadersManager.clearSession();

    // Nobody signed in and no account saved: nothing to sign out, and
    // nothing for the wipe or the other tabs to hear about. A Wander switch
    // during a sign-in that saved nothing lands here, as can a second
    // sign-out racing the first.
    if (_currentUser == null && !await _hasSavedAccount()) {
      logger.i('No account to sign out');
      // Still nothing of a sign-in that was abandoned may stay in memory:
      // drive keys and wallet signatures it held before a Wander switch.
      try {
        await _databaseHelpers.clearSessionMemory();
      } catch (e) {
        logger.w('Could not clear session memory: ${e.runtimeType}');
      }
      _injectedDriveUnlocker?.session.clear();
      _deviceUnlocker.clear();
      return;
    }

    logger.i('Logging out user');

    try {
      await _forgetPreviousAccount(address: _currentUser?.walletAddress);
    } catch (e, stacktrace) {
      logger.e('Failed to logout user', e, stacktrace);
      throw AuthenticationUnknownException('Failed to logout user');
    }

    // Signed out: the rest only makes sure storage keeps nothing of it, and
    // that a tab working on a session copy reaches the database that lasts.
    if (!fromAnotherTab) _deviceTabs.announceSignedOut();
    await _databaseHelpers.wipeAfterSignOut();
  }

  /// What the session holds in memory: signed Turbo headers, drive keys read
  /// from the tables, locked drives, wallet signatures and proven passwords.
  /// None of it may outlive the session or reach another account's.
  Future<void> _clearSessionState() async {
    TurboSignatureHeadersManager.clearSession();
    await _databaseHelpers.clearSessionMemory();
    _injectedDriveUnlocker?.session.clear();
    _deviceUnlocker.clear();
  }

  /// A sign-in with another account, once its wallet and checks have
  /// answered and just before its profile is saved: the saved account goes
  /// like a sign-out does, and other tabs hear of it. The session state is
  /// the new account's by now, so it stays. Throws when the tables can't be
  /// emptied, so nothing is saved over what is still there.
  Future<void> _forgetSwitchedAccount(
    String previousAddress,
    DeviceSecretSource source,
  ) async {
    try {
      await _forgetPreviousAccount(
        address: previousAddress,
        disconnectWander: source.method != DeviceUnlockMethod.wander,
        strict: true,
        clearSession: false,
      );
    } catch (e, stackTrace) {
      logger.e('Could not clear the previous account', e, stackTrace);
      throw AuthenticationUnknownException(
          'Could not clear the previous account from this device');
    }
    _deviceTabs.announceSignedOut();
    try {
      await _databaseHelpers.wipeAfterSignOut();
    } catch (e) {
      logger.w('Could not finish wiping the previous account: $e');
    }
  }

  /// Everything this device kept for the account that was here: the profile,
  /// the database, the session's keys and signatures, caches, stores and
  /// preferences (they clear on the signed-out event). [logout] and
  /// [_forgetSwitchedAccount] share it. [address] is that account's, when
  /// known; [strict] throws when the tables can't be emptied;
  /// [disconnectWander] is false when the new sign-in is through Wander
  /// itself; [clearSession] is false when the session state is already the
  /// next account's.
  Future<void> _forgetPreviousAccount({
    String? address,
    bool disconnectWander = true,
    bool strict = false,
    bool clearSession = true,
  }) async {
    // Signed Turbo headers belong to the account that signed them.
    if (clearSession) TurboSignatureHeadersManager.clearSession();

    // Strict: the tables first, so a failure leaves the account whole.
    if (strict) await _databaseHelpers.deleteAllTables(rethrowOnError: true);
    await _userRepository.deleteUser();

    // Past the tables and the profile, a switch (strict) must still save the
    // new account: whatever else fails here is logged and left behind. A
    // sign-out keeps its own rule and reports the failure.
    Future<void> step(Future<void> Function() run) async {
      if (!strict) return run();
      try {
        await run();
      } catch (e, stackTrace) {
        logger.w('Could not clear all of the previous account: $e');
        logger.d('$stackTrace');
      }
    }

    if (address != null) {
      await step(() => _proofStore.clear(address));
      if (disconnectWander) await _disconnectFromArConnect();
      await step(() async => (await _metadataCache).clear());
      await step(() => _secureKeyValueStore.remove('password'));
      await step(() => _secureKeyValueStore.remove('biometricEnabled'));
    }

    if (!strict) await _databaseHelpers.deleteAllTables();
    if (clearSession) {
      await _databaseHelpers.clearSessionMemory();
      // Locked drives, wallet signatures and proven passwords: memory only,
      // and none of it may outlive the session.
      _injectedDriveUnlocker?.session.clear();
      _deviceUnlocker.clear();
    }
    await step(_permanenceCache.clear);
    await step(_arnsWalletStore.clear);
    await step(_arnsPendingActionStore.clear);
    currentUser = null;
    _userStreamController.add(null);
  }

  /// The drives this device was told not to keep a key for; none if that
  /// can't be read.
  Future<Set<String>> _forgottenDriveIds() async {
    try {
      return await _databaseHelpers.driveDao.forgottenDriveIds();
    } catch (e) {
      logger.w('Could not read the drives forgotten here: $e');
      return const {};
    }
  }

  /// Whether an account is saved on this device. One that can't be told is
  /// taken as saved, so a sign-out still runs.
  Future<bool> _hasSavedAccount() async {
    try {
      return await _userRepository.hasUser();
    } catch (e) {
      logger.w('Could not tell whether an account is saved: $e');
      return true;
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

    // A drive forgotten on this device is opened only by the person: it is
    // neither tried nor signed for here, in a batch or alone.
    final forgotten = await _forgottenDriveIds();
    bool notForgotten(TransactionCommonMixin tx) =>
        !forgotten.contains(tx.getTag(EntityTag.driveId));

    final heldTxs = privateDriveTxs.where(held).where(notForgotten).toList()
      ..sort(likeliestFirst);
    final rest = privateDriveTxs
        .where((tx) => !held(tx))
        .where(notForgotten)
        .toList()
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

    // Nothing to try the password on (the gateway is down, say): no
    // approval is asked for, and the error below says why.
    if (batches && data.any((d) => d != null)) {
      final batch = await _driveUnlocker.signInOneApproval(
        wallet: wallet,
        driveIds: [
          for (final tx in rest)
            // A v1 drive without a stored signature needs its own v1
            // signature: it is left to its own attempt.
            if (await _driveUnlocker.opensWithV2Signature(
              wallet: wallet,
              driveId: tx.getTag(EntityTag.driveId)!,
              signatureType: DriveSignatureType.fromString(
                  tx.getTag(EntityTag.signatureType) ?? '1'),
            ))
              tx.getTag(EntityTag.driveId)!,
        ],
        promptBudget: promptBudget,
      );

      if (batch == DriveSignatureBatch.declined) {
        // The user said no to their wallet: one no for every drive.
        await _markSignInPassword(address, proven: false);
        throw const PasswordOpensNoDriveException();
      }

      // The batch signed every drive's v2 item, which is all a v2 drive (or a
      // v1 drive with a stored signature) needs. A v1 drive without one still
      // needs its own v1 signature, a prompt, so v2-tagged drives go first:
      // the password usually opens one of them for the batch alone.
      _v2First(candidates, data, readErrors);
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
        case DriveUnlockFailure.notTried:
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

  /// Reorders [candidates], and their [data] and [readErrors] with them, so
  /// drives tagged `Signature-Type: 2` come first, each group keeping its
  /// order.
  static void _v2First(
    List<TransactionCommonMixin> candidates,
    List<Uint8List?> data,
    List<Object?> readErrors,
  ) {
    bool isV2(int i) =>
        candidates[i].getTag(EntityTag.signatureType) ==
        DriveSignatureType.v2.value;
    final order = [
      for (var i = 0; i < candidates.length; i++)
        if (isV2(i)) i,
      for (var i = 0; i < candidates.length; i++)
        if (!isV2(i)) i,
    ];
    final c = [for (final i in order) candidates[i]];
    final d = [for (final i in order) data[i]];
    final r = [for (final i in order) readErrors[i]];
    for (var i = 0; i < order.length; i++) {
      candidates[i] = c[i];
      data[i] = d[i];
      readErrors[i] = r[i];
    }
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

/// The account saved on this device, unopened.
class SavedAccount {
  const SavedAccount({
    required this.address,
    required this.profileType,
    required this.unlockMethod,
    required this.sourceWalletAddress,
    required this.publicKey,
  });

  final String address;
  final ProfileType profileType;

  /// How it opens; null for a method this build doesn't know.
  final DeviceUnlockMethod? unlockMethod;

  /// The Ethereum or Solana address it was derived from, if any.
  final String? sourceWalletAddress;
  final String publicKey;

  /// Which browser wallet signs this account in, or null for an account its
  /// password opens (keyfile, recovery phrase, generated).
  ///
  /// A profile saved before 3.0, under a password, by an account a browser
  /// wallet now signs in to without one (Wander, Phantom, Solflare), counts
  /// as that wallet's: see [isLegacyWalletProfile]. A MetaMask account
  /// saved that way keeps its password: its password picks its wallet.
  DeviceUnlockMethod? get walletMethod {
    final method = unlockMethod;
    if (method != null && method != DeviceUnlockMethod.password) return method;
    if (method == null) return null;
    if (profileType == ProfileType.arConnect) return DeviceUnlockMethod.wander;
    final source = sourceWalletAddress;
    if (source != null && !source.startsWith('0x')) {
      return DeviceUnlockMethod.solana;
    }
    return null;
  }

  /// Saved before 3.0 under a password that a browser wallet now replaces:
  /// opening it with the wallet makes a new profile, and the drive keys the
  /// old one remembered are dropped.
  bool get isLegacyWalletProfile =>
      unlockMethod == DeviceUnlockMethod.password && walletMethod != null;
}

/// The wallet didn't give the device key: [status] says why. Nothing was
/// saved or opened.
class DeviceUnlockRefusedException implements UntrackedException {
  const DeviceUnlockRefusedException(this.status);

  final DeviceUnlockStatus status;

  @override
  String toString() => 'DeviceUnlockRefusedException(${status.name})';
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
