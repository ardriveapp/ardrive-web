import 'dart:async';

import 'package:ardrive/locked_drives/domain/drive_unlocker.dart';
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

  /// Anything else that stopped the check.
  networkError,

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
  })  : _unlocker = unlocker,
        _wallet = wallet,
        _profileKey = profileKey,
        _syncDrives = syncDrives,
        super(const UnlockDriveState());

  final String driveId;
  final DriveUnlocker _unlocker;
  final Wallet _wallet;
  final SecretKey? _profileKey;
  final Future<void> Function(List<String> driveIds) _syncDrives;

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
    if (state.status == UnlockDriveStatus.working ||
        state.status == UnlockDriveStatus.unlocked) {
      return;
    }

    emit(const UnlockDriveState(status: UnlockDriveStatus.working));

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
