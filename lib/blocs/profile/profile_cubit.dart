import 'dart:async';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/publication/domain/publication_mode.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arconnect/arconnect_prompt.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
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
  StreamSubscription<User?>? _authSubscription;

  ProfileCubit({
    required TurboUploadService turboUploadService,
    required ProfileDao profileDao,
    required Database db,
    required TabVisibilitySingleton tabVisibilitySingleton,
    required ArDriveAuth arDriveAuth,
    ArConnectService? arConnectService,
  })  : _turboUploadService = turboUploadService,
        _profileDao = profileDao,
        _db = db,
        _tabVisibilitySingleton = tabVisibilitySingleton,
        _arDriveAuth = arDriveAuth,
        _arConnect = arConnectService ?? ArConnectService(),
        super(ProfileCheckingAvailability()) {
    // ArDriveAuth publishes the user again whenever it changes, notably when
    // the background balance refresh after login lands. Without following it,
    // a balance that fell back to zero at login would stay zero here until
    // something called [refreshBalance].
    _authSubscription =
        _arDriveAuth.onAuthStateChanged().listen(_followAuthUser);
    promptToAuthenticate();
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
      // A publication has no account, and its in-memory database holds only
      // the publication it imported: forgetting "visitor drives" would delete it.
      if (!PublicationMode.isOn) await _forgetVisitorDrives();
      emit(ProfilePromptAdd());
      return;
    }

    emit(ProfilePromptLogIn());
  }

  /// With no profile, whatever the database holds was written by a visitor in
  /// an earlier session: drives opened from the sign-in screen or a share
  /// link, with their folder and file names decrypted. Nobody signed in to
  /// keep them, and the next person to use this browser must not inherit
  /// them, so a start without a profile begins empty. A drive a visitor opens
  /// now and carries into sign-in is written after this, and kept.
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
  Future<bool> checkIfWalletMismatch() =>
      _checkIfWalletMismatch(askPerson: true);

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

  /// Whether Wander is on a wallet other than [savedPublicKey]'s, or has
  /// taken back ArDrive's permissions. Either way the account here can't
  /// write through it, so both are handled as a switch.
  Future<bool> _wanderIsElsewhere(String savedPublicKey) async {
    if (!await _arConnect.checkPermissions()) {
      logger.w('ArConnect permissions changed');
      return true;
    }

    return await _arConnect.getPublicKey() != savedPublicKey;
  }

  /// Returns true if a logout flow is initiated as a result of a detected wallet or permissions change
  Future<bool> logoutIfWalletMismatch() async {
    final isMismatch = await checkIfWalletMismatch();
    if (isMismatch) {
      await logoutProfile();
    }
    return isMismatch;
  }

  /// [logoutIfWalletMismatch] for the check a sync runs in the background.
  ///
  /// Quiet: it asks Wander only once Wander has answered in this session,
  /// so it never brings up Wander's unlock prompt on its own; it asks the
  /// person nothing; and no answer counts as no mismatch. A switch while the
  /// app is open is also caught by Wander's walletSwitch event, and anything
  /// else at the next write.
  Future<bool> logoutIfWalletMismatchInBackground() async {
    if (!ArConnectPrompt.hasAnswered) return false;

    try {
      final isMismatch = await _checkIfWalletMismatch(askPerson: false);
      if (isMismatch) await logoutProfile();
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
