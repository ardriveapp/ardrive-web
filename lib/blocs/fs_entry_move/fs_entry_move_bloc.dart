import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:drift/drift.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
// ignore: depend_on_referenced_packages
import 'package:platform/platform.dart';

part 'fs_entry_move_event.dart';
part 'fs_entry_move_state.dart';

class FsEntryMoveBloc extends Bloc<FsEntryMoveEvent, FsEntryMoveState> {
  final String driveId;
  final List<ArDriveDataTableItem> _selectedItems;

  final ArweaveService _arweave;
  final TurboUploadService _turboUploadService;
  final DriveDao _driveDao;
  final ProfileCubit _profileCubit;
  final ArDriveCrypto _crypto;

  FsEntryMoveBloc({
    required this.driveId,
    required List<ArDriveDataTableItem> selectedItems,
    required ArweaveService arweave,
    required TurboUploadService turboUploadService,
    required DriveDao driveDao,
    required ProfileCubit profileCubit,
    required SyncCubit syncCubit,
    required ArDriveCrypto crypto,
    Platform platform = const LocalPlatform(),
  })  : _selectedItems = List.from(selectedItems, growable: false),
        _arweave = arweave,
        _turboUploadService = turboUploadService,
        _driveDao = driveDao,
        _profileCubit = profileCubit,
        _crypto = crypto,
        super(const FsEntryMoveLoadInProgress()) {
    if (_selectedItems.isEmpty) {
      addError(Exception('selectedItems cannot be empty'));
    }

    final profile = _profileCubit.state as ProfileLoggedIn;

    on<FsEntryMoveEvent>(
      (event, emit) async {
        if (await _profileCubit.logoutIfWalletMismatch()) {
          emit(const FsEntryMoveWalletMismatch());
          return;
        }

        if (event is FsEntryMoveInitial) {
          final drive = await _driveDao.driveById(driveId: driveId).getSingle();
          await loadFolder(folderId: drive.rootFolderId, emit: emit);
        }

        if (event is FsEntryMoveSubmit) {
          final folderInView = event.folderInView;
          final conflictingItems = await checkForConflicts(
            parentFolder: folderInView,
            profile: profile,
          );

          if (conflictingItems.isEmpty) {
            emit(const FsEntryMoveLoadInProgress());

            try {
              await moveEntities(
                conflictingItems: conflictingItems,
                profile: profile,
                parentFolder: folderInView,
                showHiddenItems: event.showHiddenItems,
              );
            } catch (err, stacktrace) {
              // TODO: we must handle this error better. Currently, if an error occurs, it will emit the success state anyway.
              logger.e('Error moving items', err, stacktrace);
            }
            emit(const FsEntryMoveSuccess());
          } else {
            emit(
              FsEntryMoveNameConflict(
                conflictingItems: conflictingItems,
                folderInView: folderInView,
                allItems: _selectedItems,
              ),
            );
          }
        }

        if (event is FsEntryMoveSkipConflicts) {
          emit(const FsEntryMoveLoadInProgress());
          final folderInView = event.folderInView;
          await moveEntities(
            parentFolder: folderInView,
            conflictingItems: event.conflictingItems,
            profile: profile,
            showHiddenItems: event.showHiddenItems,
          );
          emit(const FsEntryMoveSuccess());
        }

        if (event is FsEntryMoveUpdateTargetFolder) {
          await loadFolder(folderId: event.folderId, emit: emit);
        }

        if (event is FsEntryMoveGoBackToParent) {
          await loadParentFolder(folder: event.folderInView, emit: emit);
        }
      },
      transformer: restartable(),
    );
  }

  Future<void> loadParentFolder({
    required FolderEntry folder,
    required Emitter<FsEntryMoveState> emit,
  }) async {
    final parentFolder = folder.parentFolderId;
    if (parentFolder != null) {
      return loadFolder(folderId: parentFolder, emit: emit);
    }
  }

  Future<void> loadFolder({
    required String folderId,
    required Emitter<FsEntryMoveState> emit,
  }) async {
    final folderStream = _driveDao.watchFolderContents(
      driveId,
      folderId: folderId,
    );
    await emit.forEach(
      folderStream,
      onData: (FolderWithContents folderWithContents) => FsEntryMoveLoadSuccess(
        viewingRootFolder: folderWithContents.folder.parentFolderId == null,
        viewingFolder: folderWithContents,
        itemsToMove: _selectedItems,
      ),
    );
  }

  Future<List<ArDriveDataTableItem>> checkForConflicts({
    required final FolderEntry parentFolder,
    required ProfileLoggedIn profile,
  }) async {
    final conflictingItems = <ArDriveDataTableItem>[];
    try {
      for (var itemToMove in _selectedItems) {
        final entityWithSameNameExists =
            await _driveDao.doesEntityWithNameExist(
          name: itemToMove.name,
          driveId: driveId,
          parentFolderId: parentFolder.id,
        );

        if (entityWithSameNameExists) {
          conflictingItems.add(itemToMove);
        }
      }
    } catch (err) {
      addError(err);
    }
    return conflictingItems;
  }

  Future<void> moveEntities({
    required FolderEntry parentFolder,
    List<ArDriveDataTableItem> conflictingItems = const [],
    required ProfileLoggedIn profile,
    required bool showHiddenItems,
  }) async {
    final driveKey =
        await _driveDao.getDriveKey(driveId, profile.user.cipherKey);
    final moveTxDataItems = <DataItem>[];
    final files = _selectedItems.whereType<FileDataTableItem>().toList();

    if (!showHiddenItems) {
      files.removeWhere((element) => element.isHidden);
    }

    final filesToMove = files
        .where((file) => conflictingItems
            .where((conflictingFile) => conflictingFile.id == file.id)
            .isEmpty)
        .toList();

    files.clear();

    final folders = _selectedItems.whereType<FolderDataTableItem>().toList();

    if (!showHiddenItems) {
      folders.removeWhere((element) => element.isHidden);
    }

    final foldersToMove = folders
        .whereType<FolderDataTableItem>()
        .where((folder) => conflictingItems
            .where((conflictingFolder) => conflictingFolder.id == folder.id)
            .isEmpty)
        .toList();

    folders.clear();

    final folderMap = <String, FolderEntriesCompanion>{};

    await _driveDao.transaction(() async {
      for (var fileToMove in filesToMove) {
        var file = await _driveDao.fileById(fileId: fileToMove.id).getSingle();
        file = file.copyWith(
            parentFolderId: parentFolder.id, lastUpdated: DateTime.now());
        final fileKey = driveKey != null
            ? await _crypto.deriveFileKey(driveKey, file.id)
            : null;

        final fileEntity = file.asEntity();

        final fileDataItem = await _arweave.prepareEntityDataItem(
          fileEntity,
          profile.user.wallet,
          key: fileKey,
        );

        moveTxDataItems.add(fileDataItem);

        await _driveDao.writeToFile(file);
        fileEntity.txId = fileDataItem.id;

        await _driveDao.insertFileRevision(fileEntity.toRevisionCompanion(
          performedAction: RevisionAction.move,
        ));
      }

      for (var folderToMove in foldersToMove) {
        var folder =
            await _driveDao.folderById(folderId: folderToMove.id).getSingle();
        folder = folder.copyWith(
          parentFolderId: Value(parentFolder.id),
          lastUpdated: DateTime.now(),
        );

        final folderEntity = folder.asEntity();

        final folderDataItem = await _arweave.prepareEntityDataItem(
          folderEntity,
          profile.user.wallet,
          key: driveKey,
        );

        moveTxDataItems.add(folderDataItem);

        await _driveDao.writeToFolder(folder);

        folderEntity.txId = folderDataItem.id;

        await _driveDao.insertFolderRevision(folderEntity.toRevisionCompanion(
          performedAction: RevisionAction.move,
        ));

        folderMap.addAll({folder.id: folder.toCompanion(false)});
      }
    });

    if (_turboUploadService.useTurboUpload) {
      for (var dataItem in moveTxDataItems) {
        await _turboUploadService.postDataItem(
          dataItem: dataItem,
          wallet: profile.user.wallet,
        );
      }
    } else {
      final moveTx = await _arweave.prepareDataBundleTx(
        await DataBundle.fromDataItems(
          items: moveTxDataItems,
        ),
        profile.user.wallet,
      );
      await _arweave.postTx(moveTx);
    }
  }
}
