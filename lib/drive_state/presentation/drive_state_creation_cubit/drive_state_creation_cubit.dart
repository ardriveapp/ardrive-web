import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/drive_state/domain/drive_state_creation_service.dart';
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
/// checks the D3 precondition, exports, seals, and lands on
/// [DriveStateCreationReady] holding the artifact and the numbers the modal
/// shows. [publish] is reached only from the confirm button, and is the only
/// method that touches [DriveStateUploader].
///
/// Nothing here publishes on its own. There is no auto-confirm, no retry that
/// re-enters [publish], and the constructor starts no work.
class DriveStateCreationCubit extends Cubit<DriveStateCreationState> {
  final String driveId;

  final DriveStateCreationService _service;
  final DriveStateUploader _uploader;
  final ProfileCubit _profileCubit;
  final DriveDao _driveDao;

  DriveStateCreationCubit({
    required this.driveId,
    required DriveStateCreationService service,
    required DriveStateUploader uploader,
    required ProfileCubit profileCubit,
    required DriveDao driveDao,
  })  : _service = service,
        _uploader = uploader,
        _profileCubit = profileCubit,
        _driveDao = driveDao,
        super(DriveStateCreationInitial());

  /// Builds the artifact and stops. Emits [DriveStateCreationReady] with
  /// something that has not been sent anywhere.
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

      emit(DriveStateCreationReady(result.artifact!));
    } catch (e, stackTrace) {
      logger.e('[drive-state] preparing an artifact failed', e, stackTrace);
      emit(DriveStateCreationFailure(
        'The artifact could not be prepared. Try again.',
      ));
    }
  }

  /// Publishes the prepared artifact. Reachable only from the confirm button,
  /// and only from [DriveStateCreationReady] — a state that exists solely
  /// because a user was shown what would be published and agreed to it.
  Future<void> publish() async {
    final ready = state;
    if (ready is! DriveStateCreationReady) {
      logger.w(
        '[drive-state] publish called in ${state.runtimeType}; ignoring',
      );
      return;
    }

    emit(DriveStateCreationPublishing(ready.artifact));

    try {
      final result = await _uploader.publish(ready.artifact);

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
