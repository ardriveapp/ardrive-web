import 'dart:async';
import 'dart:convert';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/core/crypto/crypto.dart';
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
  final SecretKey? _profileKey;

  final driveNameController = TextEditingController();
  final driveKeyController = TextEditingController();
  final driveIdController = TextEditingController();

  late DriveKey? _driveKey;

  DriveAttachCubit({
    DriveID? initialDriveId,
    String? initialDriveName,
    DriveKey? initialDriveKey,
    SecretKey? profileKey,
    required ArweaveService arweave,
    required DriveDao driveDao,
    required SyncCubit syncBloc,
    required DrivesCubit drivesBloc,
  })  : _arweave = arweave,
        _driveDao = driveDao,
        _syncBloc = syncBloc,
        _drivesBloc = drivesBloc,
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
          await driveNameLoader();

          if (isClosed) {
            return;
          }

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

          if (driveNameController.text.isNotEmpty &&
              driveKeyController.text.isNotEmpty) {
            submit();
          }
        }
      }
    });

    if (driveName != null && driveName.isNotEmpty) {
      driveNameController.text = driveName;
    }
  }

  Future<bool> _checkForSnapshots(String driveId) async {
    try {
      final snapshotsStream = _arweave.getAllSnapshotsOfDrive(
        driveId,
        null, // No lastBlockHeight filter for checking
        ownerAddress: null, // Allow snapshots from any owner
      );
      
      final snapshots = await snapshotsStream.take(1).toList();
      final hasSnapshots = snapshots.isNotEmpty;
      
      if (hasSnapshots) {
        logger.i('Drive $driveId has snapshots - will enable performance optimization');
      } else {
        logger.d('Drive $driveId has no snapshots - will use standard sync');
      }
      
      return hasSnapshots;
    } catch (e) {
      logger.w('Error checking for snapshots on drive $driveId: $e');
      return false;
    }
  }

  void submit() async {
    final driveId = driveIdController.text;
    final driveName = driveNameController.text;

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

      final driveEntity = await _arweave.getLatestDriveEntityWithId(
        driveId,
        driveKey: _driveKey?.key,
      );

      if (driveEntity == null) {
        emit(DriveAttachDriveNotFound());
        emit(DriveAttachInitial());
        return;
      }

      await _driveDao.writeDriveEntity(
        name: driveName,
        entity: driveEntity,
        driveKey: _driveKey,
        profileKey: _profileKey,
      );

      // Check for snapshots to provide better user feedback
      final hasSnapshots = await _checkForSnapshots(driveId);
      
      // Don't emit success yet - go straight to syncing state
      
      /// Wait for the sync to finish before syncing the newly attached drive.
      await _syncBloc.waitCurrentSync();

      /// Show syncing state while the drive syncs
      emit(DriveAttachSyncing(hasSnapshots: hasSnapshots));

      /// Start the sync in the background
      /// Don't await it so the user can close the modal if they want
      _syncBloc.syncSingleDrive(driveId).then((_) {
        if (!isClosed) {
          /// Select the drive after sync completes
          _drivesBloc.selectDrive(driveId);
        }
      }).catchError((err) {
        logger.e('Error during background sync of attached drive', err);
      });
      
      // Give the UI time to show the syncing state before allowing the user to close
      await Future.delayed(const Duration(seconds: 2));
      
      // Check if still in syncing state (user hasn't closed the modal)
      if (!isClosed && state is DriveAttachSyncing) {
        /// Emit success to indicate the attach is complete
        /// The sync continues in the background
        emit(DriveAttachSuccess());
      }

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

    if (state is DriveAttachPrivate) {
      _driveKey = await getDriveKey(promptedDriveKey);

      if (_driveKey == null) {
        return false;
      }
    }

    final drive = await _arweave.getLatestDriveEntityWithId(driveId,
        driveKey: _driveKey?.key);

    if (drive == null) {
      return false;
    }

    driveNameController.text = drive.name!;
    return true;
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

    driveNameController.text = drive.name!;

    return null;
  }

  Future drivePrivacyLoader() async {
    final driveId = driveIdController.text;

    if (driveId.isEmpty) {
      return null;
    }

    final drivePrivacy = await _arweave.getDrivePrivacyForId(driveId);

    switch (drivePrivacy) {
      case DrivePrivacyTag.private:
        emit(DriveAttachPrivate());
        break;
      case null:
        emit(DriveAttachDriveNotFound());
        break;
      default:
        return null;
    }

    return null;
  }

  void _handleError(Object error, StackTrace stackTrace) {
    logger.e('Failed to attach drive. Emitting error', error, stackTrace);

    emit(DriveAttachFailure());
  }
}
