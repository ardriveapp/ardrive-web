import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
// ignore: depend_on_referenced_packages
import 'package:platform/platform.dart';

part 'fs_entry_license_event.dart';
part 'fs_entry_license_state.dart';

class FsEntryLicenseBloc
    extends Bloc<FsEntryLicenseEvent, FsEntryLicenseState> {
  final String driveId;
  final List<ArDriveDataTableItem> selectedItems;

  final ArweaveService _arweave;
  final TurboUploadService _turboUploadService;
  final DriveDao _driveDao;
  final ProfileCubit _profileCubit;
  final SyncCubit _syncCubit;

  FsEntryLicenseBloc({
    required this.driveId,
    required this.selectedItems,
    required ArweaveService arweave,
    required TurboUploadService turboUploadService,
    required DriveDao driveDao,
    required ProfileCubit profileCubit,
    required SyncCubit syncCubit,
    required ArDriveCrypto crypto,
    Platform platform = const LocalPlatform(),
  })  : _arweave = arweave,
        _turboUploadService = turboUploadService,
        _driveDao = driveDao,
        _profileCubit = profileCubit,
        _syncCubit = syncCubit,
        super(const FsEntryLicenseLoadInProgress()) {
    if (selectedItems.isEmpty) {
      addError(Exception('selectedItems cannot be empty'));
    }

    if (selectedItems.any((item) => item is! FileDataTableItem)) {
      addError(Exception('selectedItems must only contain files'));
    }

    final profile = _profileCubit.state as ProfileLoggedIn;

    on<FsEntryLicenseEvent>(
      (event, emit) async {
        if (await _profileCubit.logoutIfWalletMismatch()) {
          emit(const FsEntryLicenseWalletMismatch());
          return;
        }

        if (event is FsEntryLicenseInitial) {
          final drive = await _driveDao.driveById(driveId: driveId).getSingle();
          await loadFolder(folderId: drive.rootFolderId, emit: emit);
        }

        if (event is FsEntryLicenseSubmit) {
          final folderInView = event.folderInView;

          emit(const FsEntryLicenseLoadInProgress());

          try {
            await licenseEntities(
              profile: profile,
              parentFolder: folderInView,
            );
          } catch (err) {
            logger.e('Error moving items', err);
          }
          emit(const FsEntryLicenseSuccess());
        }
      },
      transformer: restartable(),
    );
  }

  Future<void> loadFolder({
    required String folderId,
    required Emitter<FsEntryLicenseState> emit,
  }) async {
    final folderStream =
        _driveDao.watchFolderContents(driveId, folderId: folderId);
    await emit.forEach(
      folderStream,
      onData: (FolderWithContents folderWithContents) =>
          FsEntryLicenseLoadSuccess(
        viewingFolder: folderWithContents,
        itemsToLicense: selectedItems,
      ),
    );
  }

  Future<void> licenseEntities({
    required FolderEntry parentFolder,
    required ProfileLoggedIn profile,
  }) async {
    final licenseAssertionTxDataItems = <DataItem>[];

    final filesToLicense =
        selectedItems.whereType<FileDataTableItem>().toList();

    await _driveDao.transaction(() async {
      for (var fileToLicense in filesToLicense) {
        // TODO: Change from move to license
        var file = await _driveDao
            .fileById(driveId: driveId, fileId: fileToLicense.id)
            .getSingle();
        file = file.copyWith(
            parentFolderId: parentFolder.id,
            path: '${parentFolder.path}/${file.name}',
            lastUpdated: DateTime.now());

        final fileEntity = file.asEntity();

        final fileDataItem = await _arweave.prepareEntityDataItem(
          fileEntity,
          profile.wallet,
        );

        licenseAssertionTxDataItems.add(fileDataItem);

        await _driveDao.writeToFile(file);
        fileEntity.txId = fileDataItem.id;

        await _driveDao.insertFileRevision(fileEntity.toRevisionCompanion(
          performedAction: RevisionAction.move,
        ));
        // END TODO: Change from move to license
      }
    });

    if (_turboUploadService.useTurboUpload) {
      for (var dataItem in licenseAssertionTxDataItems) {
        await _turboUploadService.postDataItem(
          dataItem: dataItem,
          wallet: profile.wallet,
        );
      }
    } else {
      final moveTx = await _arweave.prepareDataBundleTx(
        await DataBundle.fromDataItems(
          items: licenseAssertionTxDataItems,
        ),
        profile.wallet,
      );
      await _arweave.postTx(moveTx);
    }

    await _syncCubit.generateFsEntryPaths(driveId, {}, {});
  }
}
