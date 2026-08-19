import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart' show UploadMethod;
import 'package:ardrive/drive_state/domain/drive_state_creation_service.dart';
import 'package:ardrive/drive_state/domain/drive_state_publish_cost.dart';
import 'package:ardrive/drive_state/domain/drive_state_uploader.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'drive_state_creation_state.dart';

/// Drives the two-step creation flow: prepare, then — only if the user says
/// so — publish.
///
/// The split is the point. [prepare] does everything that costs nothing:
/// checks the D3 precondition, exports, seals, prices the result, and lands on
/// [DriveStateCreationReady] holding the artifact and the numbers the modal
/// shows. [publish] is reached only from the confirm button, and is the only
/// method that touches [DriveStateUploader].
///
/// Nothing here publishes on its own. There is no auto-confirm, no retry that
/// re-enters [publish], and the constructor starts no work.
///
/// Pricing is part of preparation rather than of confirmation, and the failure
/// to price is a hard stop: an artifact whose cost could not be established is
/// never offered for confirmation, because the whole purpose of the
/// confirmation is to show a price that cannot be taken back once paid.
class DriveStateCreationCubit extends Cubit<DriveStateCreationState> {
  final String driveId;

  final DriveStateCreationService _service;
  final DriveStateUploader _uploader;
  final DriveStatePublishCostEstimator _costEstimator;
  final ProfileCubit _profileCubit;
  final DriveDao _driveDao;

  /// How long to wait after a top-up before re-reading the Turbo balance.
  ///
  /// The payment backend credits asynchronously, so reading immediately shows
  /// the old number and the user sees their top-up do nothing. Injectable only
  /// so tests do not sit through it.
  final Duration turboBalanceRefreshDelay;

  DriveStateCreationCubit({
    required this.driveId,
    required DriveStateCreationService service,
    required DriveStateUploader uploader,
    required DriveStatePublishCostEstimator costEstimator,
    required ProfileCubit profileCubit,
    required DriveDao driveDao,
    this.turboBalanceRefreshDelay = const Duration(seconds: 2),
  })  : _service = service,
        _uploader = uploader,
        _costEstimator = costEstimator,
        _profileCubit = profileCubit,
        _driveDao = driveDao,
        super(DriveStateCreationInitial());

  /// Builds the artifact, prices it, and stops. Emits
  /// [DriveStateCreationReady] with something that has not been sent anywhere.
  Future<void> prepare() async {
    emit(DriveStateCreationPreparing());

    try {
      final profile = _profileCubit.state;
      if (profile is! ProfileLoggedIn) {
        emit(DriveStateCreationRefused(
          refusal: DriveStateCreationRefusal.notDriveOwner,
          reason: 'Log in with the drive owner\'s wallet to publish its '
              'state.',
        ));
        return;
      }

      final driveKey = await _driveDao.getDriveKey(
        driveId,
        profile.user.cipherKey,
      );

      if (driveKey == null) {
        emit(DriveStateCreationRefused(
          refusal: DriveStateCreationRefusal.publicDriveUnsupported,
          reason:
              'Drive state artifacts are only available for private drives.',
        ));
        return;
      }

      final result = await _service.prepare(
        driveId: driveId,
        driveKey: driveKey.key,
        wallet: profile.user.wallet,
      );

      if (result.isRefused) {
        logger.i(
          '[drive-state] refused to prepare an artifact for $driveId: '
          '${result.refusal!.name}',
        );

        emit(DriveStateCreationRefused(
          refusal: result.refusal!,
          reason: result.reason,
        ));
        return;
      }

      final artifact = result.artifact!;

      final DriveStatePublishCost cost;
      try {
        cost = await _costEstimator.estimate(
          sizeInBytes: artifact.sizeInBytes,
          wallet: profile.user.wallet,
          walletBalance: profile.user.walletBalance,
        );
      } catch (e, stackTrace) {
        logger.e(
          '[drive-state] could not price an artifact for $driveId',
          e,
          stackTrace,
        );
        emit(DriveStateCreationFailure(
          'The cost of publishing could not be determined, so nothing is '
          'being offered for confirmation. Nothing was uploaded and nothing '
          'was spent.',
        ));
        return;
      }

      emit(DriveStateCreationReady(
        artifact: artifact,
        cost: cost,
        method: cost.defaultMethod,
      ));
    } catch (e, stackTrace) {
      logger.e('[drive-state] preparing an artifact failed', e, stackTrace);
      emit(DriveStateCreationFailure(
        'The artifact could not be prepared. Try again.',
      ));
    }
  }

  /// Switches the transport the user would pay with. Changes what the confirm
  /// button costs and whether it is enabled; publishes nothing.
  void setUploadMethod(UploadMethod method) {
    final ready = state;
    if (ready is! DriveStateCreationReady) return;

    emit(ready.copyWith(method: method));
  }

  /// Re-reads the balances after a Turbo top-up, so the confirm button stops
  /// being disabled once the credits land. Re-prices nothing else and
  /// publishes nothing.
  Future<void> refreshTurboBalance() async {
    final ready = state;
    if (ready is! DriveStateCreationReady) return;

    final profile = _profileCubit.state;
    if (profile is! ProfileLoggedIn) return;

    await Future.delayed(turboBalanceRefreshDelay);

    try {
      final cost = await _costEstimator.estimate(
        sizeInBytes: ready.artifact.sizeInBytes,
        wallet: profile.user.wallet,
        walletBalance: profile.user.walletBalance,
      );

      if (isClosed) return;

      final current = state;
      if (current is! DriveStateCreationReady) return;

      emit(current.copyWith(cost: cost));
    } catch (e) {
      // The prices already on screen remain true; a failed refresh must not
      // throw away a prepared artifact the user paid CPU time for.
      logger.w('[drive-state] could not refresh the Turbo balance: $e');
    }
  }

  /// Publishes the prepared artifact. Reachable only from the confirm button,
  /// and only from [DriveStateCreationReady] — a state that exists solely
  /// because a user was shown what would be published, and what it costs, and
  /// agreed to it.
  Future<void> publish() async {
    final ready = state;
    if (ready is! DriveStateCreationReady) {
      logger.w(
        '[drive-state] publish called in ${state.runtimeType}; ignoring',
      );
      return;
    }

    // The button is disabled in this case, so reaching here means the UI and
    // the state disagreed. Spending money on the strength of a stale frame is
    // not a risk worth taking, so the cubit refuses independently.
    if (!ready.canPublish) {
      logger.w(
        '[drive-state] publish called with an unaffordable artifact; ignoring',
      );
      return;
    }

    emit(DriveStateCreationPublishing(ready.artifact));

    try {
      final result = await _uploader.publish(
        ready.artifact,
        method: ready.effectiveMethod,
      );

      if (result.isPublished) {
        emit(DriveStateCreationPublished(
          artifact: ready.artifact,
          txId: result.txId!,
        ));
      } else {
        emit(DriveStateCreationFailure(result.reason!));
      }
    } catch (e, stackTrace) {
      logger.e('[drive-state] publishing an artifact failed', e, stackTrace);
      emit(DriveStateCreationFailure(
        'The artifact could not be published. Nothing was spent.',
      ));
    }
  }
}
