import 'dart:async';

import 'package:ardrive/locked_drives/data/sign_in_password_proof_store.dart';
import 'package:ardrive/locked_drives/domain/drive_unlocker.dart';
import 'package:ardrive/services/arconnect/arconnect_prompt.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum UnlockDriveStatus {
  /// Waiting for a password. Also where a cancelled wallet prompt returns.
  idle,
  working,

  /// AES-GCM authentication failed: the password is wrong.
  wrongPassword,

  /// The drive couldn't be fetched to check the password. Trying again may
  /// work.
  networkError,

  /// The drive can never be read on this device: it has no drive
  /// transaction, or what decrypted isn't a drive. Trying again won't help,
  /// so Unlock stays unavailable.
  unreadable,

  /// The wallet couldn't sign, and not because the user cancelled it.
  walletFailed,

  /// The drive opened. [UnlockDriveState.openedDriveIds] says which others
  /// opened with it.
  unlocked,
}

class UnlockDriveState extends Equatable {
  const UnlockDriveState({
    this.status = UnlockDriveStatus.idle,
    this.openedDriveIds = const [],
  });

  final UnlockDriveStatus status;

  /// The drive asked for, then any others the same password opened.
  final List<String> openedDriveIds;

  @override
  List<Object?> get props => [status, openedDriveIds];
}

/// The unlock dialog's logic: one password, one drive, and optionally every
/// other locked drive it opens.
///
/// What counts as a wrong password, and what may be kept, is
/// [DriveUnlocker]'s; this only turns its answer into what the dialog says.
class UnlockDriveCubit extends Cubit<UnlockDriveState> {
  UnlockDriveCubit({
    required this.driveId,
    required DriveUnlocker unlocker,
    required Wallet wallet,
    required SecretKey? profileKey,
    required Future<void> Function(List<String> driveIds) syncDrives,
    String? signInPassword,
    SignInPasswordProofStore? proofStore,
  })  : _unlocker = unlocker,
        _signInPassword = signInPassword,
        _proofStore = proofStore,
        _wallet = wallet,
        _profileKey = profileKey,
        _syncDrives = syncDrives,
        super(const UnlockDriveState());

  final String driveId;
  final DriveUnlocker _unlocker;
  final Wallet _wallet;
  final SecretKey? _profileKey;
  final Future<void> Function(List<String> driveIds) _syncDrives;
  final String? _signInPassword;
  final SignInPasswordProofStore? _proofStore;

  /// Whether there are other locked drives to try the password on, which is
  /// whether the dialog offers to.
  bool get hasOtherLockedDrives => _unlocker.session.currentLockedDrives
      .any((drive) => drive.driveId != driveId);

  /// [remember] is "Remember on this device": the drive keys that open are
  /// stored, wrapped by the device key; without it they are kept for this
  /// session only.
  Future<void> submit({
    required String password,
    required bool tryOthers,
    bool remember = true,
  }) async {
    // An unreadable drive stays so whatever is typed: trying again can't
    // open it.
    if (state.status == UnlockDriveStatus.working ||
        state.status == UnlockDriveStatus.unlocked ||
        state.status == UnlockDriveStatus.unreadable) {
      return;
    }

    emit(const UnlockDriveState(status: UnlockDriveStatus.working));

    // Unlock is the person acting: it may ask them to reconnect Wander again
    // after an earlier Cancel.
    ArConnectPrompt.personActed();

    final DriveUnlockResult result;
    try {
      result = await _unlocker.unlock(
        wallet: _wallet,
        profileKey: _profileKey,
        driveId: driveId,
        password: password,
        tryOthers: tryOthers,
        remember: remember,
      );
    } catch (_) {
      if (!isClosed) {
        emit(const UnlockDriveState(status: UnlockDriveStatus.networkError));
      }
      return;
    }

    if (result.opened) {
      await _notePasswordOpened(
        password,
        tryOthers: tryOthers,
        remember: remember,
      );

      // Not awaited: the sync outlives the dialog, which closes now.
      unawaited(_syncDrives(result.openedDriveIds));
    }

    if (isClosed) {
      return;
    }

    if (result.opened) {
      emit(UnlockDriveState(
        status: UnlockDriveStatus.unlocked,
        openedDriveIds: result.openedDriveIds,
      ));
      return;
    }

    switch (result.failure!) {
      case DriveUnlockFailure.wrongPassword:
        emit(const UnlockDriveState(status: UnlockDriveStatus.wrongPassword));
      case DriveUnlockFailure.walletDeclined:
      // Never the dialog's answer: it always tries the password.
      case DriveUnlockFailure.notTried:
        // The user said no to their wallet. Nothing went wrong, so nothing is
        // said: the dialog is back where it was.
        emit(const UnlockDriveState());
      case DriveUnlockFailure.walletFailed:
        emit(const UnlockDriveState(status: UnlockDriveStatus.walletFailed));
      case DriveUnlockFailure.unavailable:
        emit(const UnlockDriveState(status: UnlockDriveStatus.networkError));
      case DriveUnlockFailure.unreadable:
        emit(const UnlockDriveState(status: UnlockDriveStatus.unreadable));
    }
  }

  /// If the password that opened a drive is the sign-in password, that is
  /// now proven, in the session and on this device, and new drives use it.
  /// If the sign-in password is unproven and this is another one, discovery
  /// may try it - it opened a drive - but new drives never use it: it may be
  /// an old drive's password, not the drive password.
  ///
  /// Only with [tryOthers]: unticked, the person asked for this drive alone,
  /// and a later discovery must not open the others with it. The drives
  /// discovery opens with it follow [remember].
  Future<void> _notePasswordOpened(
    String password, {
    required bool tryOthers,
    required bool remember,
  }) async {
    final owner = await _wallet.getAddress();
    final session = _unlocker.session;

    if (password == _signInPassword) {
      session.setSignInPasswordProven(owner, true);
      await (_proofStore ?? SignInPasswordProofStore()).clear(owner);
    } else if (tryOthers && session.signInPasswordProven(owner) == false) {
      session.rememberProvenDrivePassword(owner, password, keepKeys: remember);
    }
  }

  /// Typing again clears what the last attempt said.
  void edited() {
    if (state.status == UnlockDriveStatus.wrongPassword ||
        state.status == UnlockDriveStatus.networkError ||
        state.status == UnlockDriveStatus.walletFailed) {
      emit(const UnlockDriveState());
    }
  }
}
