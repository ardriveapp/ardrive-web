import 'dart:async';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/profile/profile_presence_hint.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/publication/domain/publication_mode.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arconnect/arconnect_prompt.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/utils.dart' show ownerToAddress;
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'profile_state.dart';

/// [ProfileCubit] includes logic for managing the user's profile login status
/// and wallet balance.
class ProfileCubit extends Cubit<ProfileState> {
  final TurboUploadService _turboUploadService;
  final ProfileDao _profileDao;
  final Database _db;
  final TabVisibilitySingleton _tabVisibilitySingleton;
  final ArDriveAuth _arDriveAuth;
  final ArConnectService _arConnect;
  final ProfilePresenceHint? _presenceHint;
  final ProfilePresence _presenceAtStart;
  StreamSubscription<User?>? _authSubscription;

  /// Stops listening for Wander's account switches; see [_onWanderSwitch].
  Function()? _forgetWanderSwitch;

  /// Removes this cubit as the one told when a Wander reconnect finds
  /// another wallet.
  VoidCallback? _forgetOtherWalletHandler;

  /// Set while [signOutForOtherWallet] runs, so it signs out once however
  /// many times Wander says so.
  Future<void>? _signingOutForOtherWallet;

  /// Whether the sign-in screen still owes the notice that Wander's account
  /// changed; see [takeOtherWalletNotice].
  bool _otherWalletNotice = false;

  ProfileCubit({
    required TurboUploadService turboUploadService,
    required ProfileDao profileDao,
    required Database db,
    required TabVisibilitySingleton tabVisibilitySingleton,
    required ArDriveAuth arDriveAuth,
    ArConnectService? arConnectService,
    ProfilePresenceHint? presenceHint,
  })  : _turboUploadService = turboUploadService,
        _profileDao = profileDao,
        _db = db,
        _tabVisibilitySingleton = tabVisibilitySingleton,
        _arDriveAuth = arDriveAuth,
        _arConnect = arConnectService ?? ArConnectService(),
        _presenceHint = PublicationMode.isOn ? null : presenceHint,
        _presenceAtStart = PublicationMode.isOn
            ? ProfilePresence.unknown
            : presenceHint?.atStart ?? ProfilePresence.unknown,
        super(ProfileCheckingAvailability()) {
    // ArDriveAuth publishes the user again whenever it changes, notably when
    // the background balance refresh after login lands. Without following it,
    // a balance that fell back to zero at login would stay zero here until
    // something called [refreshBalance].
    _authSubscription =
        _arDriveAuth.onAuthStateChanged().listen(_followAuthUser);
    // The one place that answers a Wander account switch, for as long as the
    // app runs: in the drives, on Welcome back, anywhere.
    _forgetWanderSwitch = onArConnectWalletSwitchTo(onWanderSwitch);
    _forgetOtherWalletHandler =
        ArConnectPrompt.registerOtherWalletHandler(signOutForOtherWallet);
    promptToAuthenticate();
  }

  /// Wander moved to another account. If this device has a saved Wander
  /// account on a different wallet, it can't write through Wander any more,
  /// so it signs out. [address] is the account Wander moved to; null is
  /// Wander saying ArDrive disconnected, which signing out itself does.
  @visibleForTesting
  Future<void> onWanderSwitch(String? address) async {
    if (address == null || isClosed) return;

    try {
      final profile = await _profileDao.defaultProfile().getSingleOrNull();
      if (profile == null ||
          profile.profileType != ProfileType.arConnect.index ||
          await ownerToAddress(profile.walletPublicKey) == address) {
        return;
      }
    } catch (e) {
      logger.w('Could not read the saved account after a Wander switch: $e');
      return;
    }

    logger.i('Wander moved to another account; signing out');
    await signOutForOtherWallet();
  }

  /// Signs out because Wander is on another wallet than the saved account,
  /// all the way: the saved account goes too, so the sign-in screen offers
  /// no Welcome back for a wallet Wander is no longer on, and it says why.
  ///
  /// Once: while one is running, another call waits for it.
  Future<void> signOutForOtherWallet() {
    return _signingOutForOtherWallet ??= () async {
      try {
        _otherWalletNotice = true;
        // Nothing still running, such as a drive unlock pass, may sign with
        // the other wallet while this signs out.
        final profile = await _profileDao.defaultProfile().getSingleOrNull();
        if (profile != null &&
            profile.profileType == ProfileType.arConnect.index) {
          ArConnectPrompt.refuseFor(profile.walletPublicKey);
        }
        await _arDriveAuth.logout();
        if (!isClosed) emit(ProfileSignedOutForOtherWallet());
      } catch (e, stackTrace) {
        logger.e('Could not sign out after a Wander switch', e, stackTrace);
        if (!isClosed) emit(ProfileSignedOutForOtherWallet());
      } finally {
        _signingOutForOtherWallet = null;
      }
    }();
  }

  /// True once after [signOutForOtherWallet], for the sign-in screen to say
  /// why it is there.
  bool takeOtherWalletNotice() {
    final owed = _otherWalletNotice;
    _otherWalletNotice = false;
    return owed;
  }

  /// Whether this device holds an account, for the sign-in panel to draw
  /// before the database has answered: what the last start recorded while
  /// the check runs, and the answer once it is in.
  ProfilePresence get presence => switch (state) {
        ProfileCheckingAvailability() => _presenceAtStart,
        ProfileAvailable() => ProfilePresence.present,
        _ => ProfilePresence.absent,
      };

  @override
  void onChange(Change<ProfileState> change) {
    super.onChange(change);
    final next = change.nextState;
    if (next is ProfileAvailable) {
      unawaited(_presenceHint?.record(present: true));
    } else if (next is ProfileUnavailable) {
      unawaited(_presenceHint?.record(present: false));
    }
  }

  Future<bool> isCurrentProfileArConnect() async {
    final profile = await _profileDao.defaultProfile().getSingleOrNull();
    if (profile != null) {
      return profile.profileType == ProfileType.arConnect.index;
    } else {
      return false;
    }
  }

  /// Where the app starts for the account saved on this device, if any.
  ///
  /// Never asks a browser wallet. A saved account unlocks with its password,
  /// checked on this device (see [ProfileDao.loadDefaultProfile]), whatever
  /// kind it is. Wander is asked only when a write or a private drive key
  /// needs it, where [checkIfWalletMismatch] catches a Wander that is now on
  /// another wallet. Asking it here kept the app on its logo while Wander was
  /// locked, for good once its unlock prompt was closed, and a Wander on
  /// another wallet deleted every drive on this device.
  Future<void> promptToAuthenticate() async {
    final profile = await _profileDao.defaultProfile().getSingleOrNull();
    // Profile unavailable - route to new profile screen
    if (profile == null) {
      // The sign-in panel first, then the clean-up, which no one waits for.
      // Started before anything can react to the panel, so whatever a
      // visitor writes from it queues behind the deletion and is kept.
      emit(ProfilePromptAdd());
      // A publication has no account, and its in-memory database holds only
      // the publication it imported: forgetting "visitor drives" would delete it.
      if (!PublicationMode.isOn) await _forgetVisitorDrives();
      return;
    }

    emit(ProfilePromptLogIn());
  }

  /// With no profile, whatever the database holds was written by a visitor in
  /// an earlier session: drives opened from the sign-in screen or a share
  /// link, with their folder and file names decrypted. Nobody signed in to
  /// keep them, and the next person to use this browser must not inherit
  /// them, so a start without a profile begins empty. A drive a visitor opens
  /// now and carries into sign-in is written after this, and kept: the
  /// deletion is one transaction, started as [ProfilePromptAdd] goes out, and
  /// drift runs every later statement after it.
  ///
  /// Never throws: the sign-in screen must open either way.
  Future<void> _forgetVisitorDrives() async {
    try {
      await _deleteAllTables();
    } catch (e, stackTrace) {
      logger.e('Failed to clear drives left by a visitor', e, stackTrace);
    }
  }

  Future<void> _deleteAllTables() => _db.transaction(() async {
        for (final table in _db.allTables) {
          await _db.delete(table).go();
        }
      });

  /// Returns true if Wander is now on another wallet than the saved account,
  /// or no longer lets ArDrive in. For any other account, false.
  ///
  /// Asked before a write. Wander is asked through [ArConnectPrompt], so a
  /// locked Wander, or one whose prompt was closed, ends in Try again rather
  /// than a wait; Cancel throws [ArConnectUnavailableException].
  ///
  /// A write is the person acting, so it may ask them to reconnect again
  /// after an earlier Cancel; see [ArConnectPrompt.personActed].
  Future<bool> checkIfWalletMismatch() {
    ArConnectPrompt.personActed();
    return _checkIfWalletMismatch(askPerson: true);
  }

  Future<bool> _checkIfWalletMismatch({required bool askPerson}) async {
    final profile = await _profileDao.defaultProfile().getSingleOrNull();

    if (profile == null || profile.profileType != ProfileType.arConnect.index) {
      return false;
    }

    try {
      return await ArConnectPrompt.ask(
        _arConnect,
        () => _wanderIsElsewhere(profile.walletPublicKey),
        askPerson: askPerson,
      );
    } on ArConnectUnavailableException {
      rethrow;
    } catch (e) {
      if (_tabVisibilitySingleton.isTabFocused()) {
        return false;
      }

      logger.e('Error checking ArConnect permissions', e);

      bool isWalletMismatch = false;

      await _tabVisibilitySingleton.onTabGetsFocusedFuture(() async {
        isWalletMismatch = await _checkIfWalletMismatch(askPerson: askPerson);
      });

      return isWalletMismatch;
    }
  }

  /// Whether Wander is on a wallet other than [savedPublicKey]'s.
  ///
  /// A Wander that has lost ArDrive's permissions, as every site's are lost
  /// when Wander updates, is not a switch: [ArConnectPrompt.ask] offers to
  /// reconnect, then asks this again.
  Future<bool> _wanderIsElsewhere(String savedPublicKey) async {
    if (!await _arConnect.checkPermissions()) {
      logger.w('Wander does not have ArDrive\'s permissions');
      throw const ArConnectMissingPermissionException();
    }

    // The address, not the public key: Wander reads its active address from
    // storage, but decrypts the wallet for its public key, which brings up
    // its unlock window when it is locked. So this check never does.
    return await _arConnect.getWalletAddress() !=
        await ownerToAddress(savedPublicKey);
  }

  /// Returns true if Wander is on another wallet, after signing out (see
  /// [signOutForOtherWallet]).
  Future<bool> logoutIfWalletMismatch() async {
    final isMismatch = await checkIfWalletMismatch();
    if (isMismatch) {
      await signOutForOtherWallet();
    }
    return isMismatch;
  }

  /// [logoutIfWalletMismatch] for the check a sync runs in the background.
  ///
  /// Quiet: it asks Wander only once Wander has answered in this session,
  /// and only for what it answers without its password (see
  /// [_wanderIsElsewhere]), so it never brings up Wander's unlock prompt on
  /// its own; it asks the person nothing; and no answer counts as no
  /// mismatch. A switch while the
  /// app is open is also caught by Wander's walletSwitch event, and anything
  /// else at the next write.
  Future<bool> logoutIfWalletMismatchInBackground() async {
    if (!ArConnectPrompt.hasAnswered) return false;

    try {
      final isMismatch = await _checkIfWalletMismatch(askPerson: false);
      if (isMismatch) await signOutForOtherWallet();
      return isMismatch;
    } on ArConnectUnavailableException catch (e) {
      logger.i('Wander did not answer the background wallet check: $e');
      return false;
    }
  }

  Future<void> unlockDefaultProfile(
    User user,
    ProfileType profileType,
  ) async {
    emit(ProfileLoggingIn());

    // Wander may be asked again for this account, and the person asked to
    // reconnect, whatever an earlier session decided.
    ArConnectPrompt.signedIn();

    // Before anyone hears the user is in: the first sync after login reads a
    // private drive's key from its row, and a drive opened as a visitor has
    // none there yet.
    await _persistVisitorDriveKeys(user);

    emit(
      ProfileLoggedIn(
        // The balance refresh that follows login can finish before the
        // profile is unlocked, so prefer ArDriveAuth's copy of the user.
        user: _authUserFor(user.walletAddress) ?? user,
        useTurbo: _turboUploadService.useTurboUpload,
      ),
    );
  }

  /// A private drive opened before signing in holds its key in memory only.
  /// Now that there is a profile key, the row gets an encrypted copy, so the
  /// drive survives a reload and the sync finds the key where it looks for a
  /// signed-in user. See [DriveDao.persistInMemoryDriveKeys]. Never throws:
  /// a login must not fail over a drive somebody looked at beforehand.
  Future<void> _persistVisitorDriveKeys(User user) async {
    try {
      final written =
          await _db.driveDao.persistInMemoryDriveKeys(user.cipherKey);

      if (written.isNotEmpty) {
        logger.i(
          'Stored the keys of ${written.length} drive(s) opened before '
          'signing in',
        );
      }
    } catch (e, stackTrace) {
      logger.e(
        'Failed to store the keys of drives opened before signing in',
        e,
        stackTrace,
      );
    }
  }

  Future<void> refreshBalance() async {
    final profile = state as ProfileLoggedIn;

    await _arDriveAuth.refreshBalance();

    // Normally already applied through [_followAuthUser]; this keeps the
    // promise that the new balance is in the state once this completes. The
    // user may have logged out during the request, which this also checks.
    _followAuthUser(_authUserFor(profile.user.walletAddress));
  }

  /// Takes on [user] if it is the user already logged in here. Logging in and
  /// out are driven by [unlockDefaultProfile] and [logoutProfile], not by this.
  void _followAuthUser(User? user) {
    final current = state;
    if (isClosed ||
        user == null ||
        current is! ProfileLoggedIn ||
        current.user.walletAddress != user.walletAddress) {
      return;
    }

    emit(current.copyWith(user: user));
  }

  /// ArDriveAuth's current user, if it is the one with [walletAddress].
  User? _authUserFor(String walletAddress) {
    try {
      final user = _arDriveAuth.currentUser;
      return user.walletAddress == walletAddress ? user : null;
    } on AuthenticationUserIsNotLoggedInException {
      return null;
    }
  }

  Future<void> logoutProfile() async {
    logger.i('Logging out profile. state: ${state.runtimeType}');
    if (state is ProfileLoggingOut) {
      emit(ProfilePromptAdd());

      logger
          .i('Profile logout already in progress. state: ${state.runtimeType}');
      return;
    }

    emit(ProfileLoggingOut());
  }

  @override
  Future<void> close() async {
    await _authSubscription?.cancel();
    _forgetWanderSwitch?.call();
    _forgetOtherWalletHandler?.call();
    return super.close();
  }

  Future<void> deleteTables() async {
    // Delete all table data.
    await _db.transaction(() async {
      for (final table in _db.allTables) {
        await _db.delete(table).go();
      }
    });
  }
}
