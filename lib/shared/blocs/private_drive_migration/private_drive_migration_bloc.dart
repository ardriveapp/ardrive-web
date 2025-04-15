import 'dart:async';
import 'dart:convert';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/drive_signature.dart';
import 'package:ardrive/entities/drive_signature_type.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:drift/drift.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

part 'private_drive_migration_event.dart';
part 'private_drive_migration_state.dart';

class PrivateDriveMigrationBloc
    extends Bloc<PrivateDriveMigrationEvent, PrivateDriveMigrationState> {
  StreamSubscription? _drivesSubscription;

  final DrivesCubit drivesCubit;
  final DriveDao driveDao;
  final ArDriveAuth ardriveAuth;
  final ArDriveCrypto crypto;
  final TurboUploadService turboUploadService;

  List<Drive> drivesRequiringMigration = [];
  Set<Drive> completedMigration = {};

  PrivateDriveMigrationBloc({
    required this.drivesCubit,
    required this.driveDao,
    required this.ardriveAuth,
    required this.crypto,
    required this.turboUploadService,
  }) : super(PrivateDriveMigrationHidden()) {
    _drivesSubscription = drivesCubit.stream.listen((state) {
      if (state is DrivesLoadSuccess) {
        add(const PrivateDriveMigrationCheck());
      }
    });

    on<PrivateDriveMigrationCloseEvent>((event, emit) {
      emit(PrivateDriveMigrationHidden());
    });

    on<PrivateDriveMigrationCheck>(_checkDrivesForMigration);

    on<PrivateDriveMigrationStartEvent>(_performDriveMigration);
    // do initial check on startup
    add(const PrivateDriveMigrationCheck());
  }

  void _checkDrivesForMigration(PrivateDriveMigrationCheck event,
      Emitter<PrivateDriveMigrationState> emit) {
    if (drivesCubit.state is DrivesLoadSuccess) {
      final drives = (drivesCubit.state as DrivesLoadSuccess).userDrives;
      drivesRequiringMigration = drives
          .where((drive) =>
              drive.privacy == 'private' &&
              (drive.signatureType == '1' || drive.signatureType == null) &&
              drive.driveKeyGenerated == true)
          .toList();
      completedMigration = {};

      if (drivesRequiringMigration.isNotEmpty) {
        emit(PrivateDriveMigrationVisible());
      } else {
        emit(PrivateDriveMigrationHidden());
      }
    }
  }

  Future<void> _performDriveMigration(PrivateDriveMigrationStartEvent event,
      Emitter<PrivateDriveMigrationState> emit) async {
    // stop listening to drivesCubit stream here
    // to ensure no more events are processed while performing migration
    _drivesSubscription?.cancel();
    _drivesSubscription = null;

    if (!(await ardriveAuth.isUserLoggedIn())) {
      emit(const PrivateDriveMigrationFailed(error: 'User is not logged in'));
    }

    final wallet = ardriveAuth.currentUser.wallet;

    try {
      for (final drive in drivesRequiringMigration) {
        if (completedMigration.contains(drive)) {
          continue;
        }
        emit(PrivateDriveMigrationInProgress(
          inProgressDrive: drive,
        ));

        final message =
            Uint8List.fromList(utf8.encode('drive') + Uuid.parse(drive.id));

        final owner = await wallet.getOwner();
        final dataItem = DataItem.withBlobData(data: message, owner: owner);
        dataItem.addTag('Action', 'Generate-Signature-V2');

        final walletSignatureV1 = await wallet.sign(message);

        final driveKeyV2 = await crypto.deriveDriveKey(wallet, drive.id,
            ardriveAuth.currentUser.password, DriveSignatureType.v2, null);

        // encrypt walletSignatureV1 with driveKeyV2
        final encryptedWalletSignatureV1 =
            await crypto.encrypt(walletSignatureV1, driveKeyV2.key);

        final driveSignature = DriveSignatureEntity(
          driveId: drive.id,
          signatureFormat: '1',
          cipherIv: utils.encodeBytesToBase64(encryptedWalletSignatureV1.nonce),
          data: encryptedWalletSignatureV1.concatenation(nonce: false),
        );

        final appInfo = AppInfoServices().appInfo;
        final driveSignatureDataItem = await driveSignature.asPreparedDataItem(
            owner: owner, appInfo: appInfo);

        await driveSignatureDataItem.sign(ArweaveSigner(wallet));

        // upload via turbo
        await turboUploadService.postDataItem(
          dataItem: driveSignatureDataItem,
          wallet: wallet,
        );

        // comment upload above and uncomment await below for dev testing
        // await Future.delayed(const Duration(seconds: 1));

        completedMigration.add(drive);

        // updated persisted and in-memory drive key values
        await driveDao.updateDrive(drive.toCompanion(true).copyWith(
              driveKeyGenerated: const Value(false),
            ));

        final driveKey = await driveDao.getDriveKeyFromMemory(drive.id);
        final updatedDriveKey = DriveKey(driveKey!.key, false);
        await driveDao.putDriveKeyInMemory(
            driveID: drive.id, driveKey: updatedDriveKey);
      }

      emit(PrivateDriveMigrationComplete());
    } catch (e) {
      emit(const PrivateDriveMigrationFailed(
          error: 'Error migrating drive, please try again.'));
    }
    // emit(PrivateDriveMigrationHidden());
  }

  @override
  Future<void> close() {
    _drivesSubscription?.cancel();
    return super.close();
  }
}
