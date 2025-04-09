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

  void submit() async {
    final driveId = driveIdController.text;
    final driveName = driveNameController.text;

    try {
      final previousState = state;
      final DrivePrivacy drivePrivacy;

      if (state is DriveAttachPrivate) {
        if (await driveKeyValidator() != null) {
          emit(DriveAttachInvalidDriveKey());
          emit(previousState);
          return;
        }

        drivePrivacy = DrivePrivacy.private;
      } else {
        drivePrivacy = DrivePrivacy.public;
      }

      if (!await driveNameLoader()) {
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

      emit(DriveAttachSuccess());

      /// Wait for the sync to finish before syncing the newly attached drive.
      await _syncBloc.waitCurrentSync();

      /// Then, sync and select the newly attached drive.
      unawaited(_syncBloc
          .startSync()
          .then((value) => _drivesBloc.selectDrive(driveId)));

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
