import 'package:ardrive/blocs/activity/activity_cubit.dart';
import 'dart:async';
import 'dart:convert';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/drive_entity.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'drive_attach_state.dart';

/// [DriveAttachCubit] includes logic for attaching drives to the user's profile.
class DriveAttachCubit extends Cubit<DriveAttachState> {
  final ArweaveService _arweave;
  final DriveDao _driveDao;
  final SyncCubit _syncBloc;
  final DrivesCubit _drivesBloc;
  final ActivityCubit _activityCubit;
  final SecretKey? _profileKey;

  final driveNameController = TextEditingController();
  final driveKeyController = TextEditingController();
  final driveIdController = TextEditingController();

  late DriveKey? _driveKey;
  DriveEntity? cachedDriveEntity;
  final ValueNotifier<bool> _lookupNotifier = ValueNotifier(false);

  ValueNotifier<bool> get lookupNotifier => _lookupNotifier;

  DriveAttachCubit({
    DriveID? initialDriveId,
    String? initialDriveName,
    DriveKey? initialDriveKey,
    SecretKey? profileKey,
    required ArweaveService arweave,
    required DriveDao driveDao,
    required SyncCubit syncBloc,
    required DrivesCubit drivesBloc,
    required ActivityCubit activityCubit,
  })  : _arweave = arweave,
        _driveDao = driveDao,
        _syncBloc = syncBloc,
        _drivesBloc = drivesBloc,
        _activityCubit = activityCubit,
        _profileKey = profileKey,
        super(DriveAttachInitial()) {
    initializeForm(
      driveId: initialDriveId,
      driveName: initialDriveName,
      driveKey: initialDriveKey,
    );
  }

  Future<void> initializeForm({
    String? driveId,
    String? driveName,
    DriveKey? driveKey,
  }) async {
    _driveKey = driveKey;

    // Add the initial drive id in a microtask to properly trigger the drive name loader.
    await Future.microtask(() async {
      if (driveId != null) {
        driveIdController.text = driveId;

        await drivePrivacyLoader();

        if (state is! DriveAttachPrivate) {
          // Public drives: drivePrivacyLoader already fetched the entity
          if (isClosed) return;

          if (driveNameController.text.isNotEmpty) {
            submit();
          }
        } else {
          if (driveName != null) {
            driveNameController.text = driveName;
          }
          if (driveKey != null) {
            driveKeyController.text = base64Encode(
              await driveKey.key.extractBytes(),
            );
          }

          // The key is the whole precondition. A private share link no longer
          // carries the drive's name - it is a secret, and `submit()` resolves
          // the real one from the drive's own record on its way through.
          //
          // Gating this on the name as well used to mean that a link whose key
          // was wrong, or whose drive could not be found, simply sat there:
          // auto-attach was skipped and nothing said why. Letting `submit()`
          // run surfaces those through the states it already emits -
          // `DriveAttachInvalidDriveKey` and `DriveAttachDriveNotFound`.
          if (driveKeyController.text.isNotEmpty) {
            submit();
          }
        }
      }
    });

    if (driveName != null && driveName.isNotEmpty) {
      driveNameController.text = driveName;
    }
  }

  void submit() async {
    final driveId = driveIdController.text;

    // Read before the loaders below overwrite the field with the drive's own
    // name. A name typed by hand is the one the drive is attached under; an
    // empty one is not a preference, so it falls back to whatever the chain
    // says once the loaders have run.
    final typedDriveName = driveNameController.text;

    try {
      final previousState = state;
      final DrivePrivacy drivePrivacy;

      if (state is DriveAttachPrivate) {
        if (await driveKeyValidator() != null) {
          if (isClosed) {
            logger.i(
                'Drive attach cubit closed. Not emitting invalid drive key.');
            return;
          }

          emit(DriveAttachInvalidDriveKey());
          emit(previousState);
          return;
        }

        drivePrivacy = DrivePrivacy.private;
      } else {
        drivePrivacy = DrivePrivacy.public;
      }

      if (!await driveNameLoader()) {
        if (isClosed) {
          logger.i('Drive attach cubit closed. Not emitting drive not found.');
          return;
        }

        emit(DriveAttachDriveNotFound());
        emit(previousState);
        return;
      }

      emit(DriveAttachInProgress());

      // Reuse cached entity from driveNameLoader to avoid redundant GraphQL call
      final driveEntity = cachedDriveEntity ??
          await _arweave.getLatestDriveEntityWithId(
            driveId,
            driveKey: _driveKey?.key,
          );

      if (driveEntity == null) {
        emit(DriveAttachDriveNotFound());
        emit(DriveAttachInitial());
        return;
      }

      final driveName = typedDriveName.isNotEmpty
          ? typedDriveName
          : driveNameController.text;

      await _driveDao.writeDriveEntity(
        name: driveName,
        entity: driveEntity,
        driveKey: _driveKey,
        profileKey: _profileKey,
      );

      emit(DriveAttachSuccess());

      /// Wait for the sync to finish before syncing the newly attached drive.
      await _syncBloc.waitCurrentSync();

      /// Then, sync only the newly attached drive and select it.
      ///
      /// `startSyncForDrive` refuses rather than queues now, and returns
      /// whether it actually ran. Between `waitCurrentSync` returning and this
      /// call another sync can take the slot - or the tab can lose focus, or
      /// an upload can be in progress - and the drive would be selected having
      /// never been read, with nothing anywhere saying so.
      ///
      /// The attach dialog itself is the reason this needs more than one try.
      /// It runs through `performUninterruptableActivity`, which holds
      /// `ActivityInProgress` until the dialog *route* finishes closing - 200ms
      /// of transition after `Navigator.pop`. `startSyncForDrive` refuses
      /// outright while that flag is up, and both attempts used to land inside
      /// that window, so attaching a drive reliably synced nothing at all.
      /// Waiting for the activity to end first is what makes the retry mean
      /// something.
      unawaited(() async {
        try {
          var didSync = await _syncBloc.startSyncForDrive(driveId: driveId);

          if (!didSync) {
            await _waitForActivityToFinish();
            await _syncBloc.waitCurrentSync();
            didSync = await _syncBloc.startSyncForDrive(driveId: driveId);
          }

          if (!didSync) {
            logger.w(
              'Attached drive $driveId was not synced; the explorer will '
              'offer to sync it.',
            );
          }

          _drivesBloc.selectDrive(driveId);
        } catch (e) {
          logger.e('Error syncing attached drive $driveId', e);
          _drivesBloc.selectDrive(driveId);
        }
      }());

      PlausibleEventTracker.trackAttachDrive(
        drivePrivacy: drivePrivacy,
      );
    } catch (err, stacktrace) {
      _handleError(err, stacktrace);
    }
  }

  Future<DriveKey?> getDriveKey(
    String? promptedDriveKey,
  ) async {
    if (promptedDriveKey == null || promptedDriveKey.isEmpty) {
      return null;
    }

    SecretKey? driveKey;

    try {
      driveKey = SecretKey(decodeBase64ToBytes(promptedDriveKey));
    } catch (e) {
      return null;
    }

    return DriveKey(driveKey, true);
  }

  Future<bool> driveNameLoader() async {
    final driveId = driveIdController.text;
    final promptedDriveKey = driveKeyController.text;

    if (driveId.isEmpty) {
      return false;
    }

    // Already have the entity cached from drivePrivacyLoader
    if (cachedDriveEntity != null) {
      driveNameController.text = cachedDriveEntity!.name!;
      return true;
    }

    if (state is DriveAttachPrivate) {
      _driveKey = await getDriveKey(promptedDriveKey);

      if (_driveKey == null) {
        return false;
      }
    }

    _lookupNotifier.value = true;

    try {
      final drive = await _arweave.getLatestDriveEntityWithId(driveId,
          driveKey: _driveKey?.key);

      if (drive == null) {
        return false;
      }

      cachedDriveEntity = drive;
      driveNameController.text = drive.name!;
      return true;
    } finally {
      _lookupNotifier.value = false;
    }
  }

  Future<String?> driveKeyValidator() async {
    final driveId = driveIdController.text;
    final promptedDriveKey = driveKeyController.text;

    if (driveId.isEmpty) {
      return 'Invalid drive key';
    }

    _driveKey = await getDriveKey(promptedDriveKey);

    final drive = await _arweave.getLatestDriveEntityWithId(driveId,
        driveKey: _driveKey?.key);

    if (drive == null) {
      return 'Invalid drive key';
    }

    cachedDriveEntity = drive;
    driveNameController.text = drive.name!;

    return null;
  }

  /// Checks drive privacy and, for public drives, fetches the entity in one flow.
  /// For private drives, emits DriveAttachPrivate so the key field appears.
  Future drivePrivacyLoader() async {
    final driveId = driveIdController.text;

    // UUID = 36 chars, but also accept base64url IDs (43 chars)
    if (driveId.isEmpty || driveId.length < 32) {
      return null;
    }

    _lookupNotifier.value = true;

    try {
      final result = await _arweave.getDrivePrivacyForId(driveId);

      if (result == null) {
        emit(DriveAttachDriveNotFound());
        return null;
      }

      switch (result.privacy) {
        case DrivePrivacyTag.private:
          emit(DriveAttachPrivate());
          break;
        case null:
          emit(DriveAttachDriveNotFound());
          break;
        default:
          // Public drive — fetch and cache entity so driveNameLoader can skip
          final drive = await _arweave.getLatestDriveEntityWithId(
            driveId,
            driveOwner: result.ownerAddress,
          );

          if (drive == null) {
            emit(DriveAttachDriveNotFound());
            return null;
          }

          cachedDriveEntity = drive;
          driveNameController.text = drive.name!;
          break;
      }
    } catch (e) {
      logger.e('Error looking up drive $driveId', e);
      emit(DriveAttachDriveNotFound());
    } finally {
      _lookupNotifier.value = false;
    }

    return null;
  }

  void _handleError(Object error, StackTrace stackTrace) {
    logger.e('Failed to attach drive. Emitting error', error, stackTrace);

    emit(DriveAttachFailure());
  }
  /// Parks until nothing uninterruptible is running.
  ///
  /// Bounded, because a flag that never clears must not strand an attach: the
  /// worst outcome of giving up is the "Drive Not Synced" card the explorer
  /// already shows, with its own Sync button.
  Future<void> _waitForActivityToFinish() async {
    if (_activityCubit.state is! ActivityInProgress) return;

    try {
      await _activityCubit.stream
          .firstWhere((state) => state is! ActivityInProgress)
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Timed out or the cubit closed. Fall through and try anyway.
    }
  }

}
