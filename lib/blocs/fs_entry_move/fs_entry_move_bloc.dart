import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/drive_detail/selected_item.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:pedantic/pedantic.dart';

part 'fs_entry_move_event.dart';
part 'fs_entry_move_state.dart';

class FsEntryMoveBloc extends Bloc<FsEntryMoveEvent, FsEntryMoveState> {
  final String driveId;
  final List<SelectedItem> selectedItems;

  final ArweaveService _arweave;
  final DriveDao _driveDao;
  final ProfileCubit _profileCubit;
  final SyncCubit _syncCubit;

  StreamSubscription? _folderSubscription;

  FsEntryMoveBloc({
    required this.driveId,
    required this.selectedItems,
    required ArweaveService arweave,
    required DriveDao driveDao,
    required ProfileCubit profileCubit,
    required SyncCubit syncCubit,
  })  : _arweave = arweave,
        _driveDao = driveDao,
        _profileCubit = profileCubit,
        _syncCubit = syncCubit,
        super(const FsEntryMoveLoadInProgress()) {
    final profile = _profileCubit.state as ProfileLoggedIn;

    on<FsEntryMoveEvent>((event, emit) async {
      if (event is FsEntryMoveInitial) {
        final drive = await _driveDao.driveById(driveId: driveId).getSingle();
        await loadFolder(folderId: drive.rootFolderId, emit: emit);
      }

      if (event is FsEntryMoveSubmit) {
        final folderInView = event.folderInView;
        await checkForConflicts(
          parentFolder: folderInView,
          profile: profile,
          emit: emit,
        );
      }

      if (event is FsEntryMoveSkipConflicts) {
        final folderInView = event.folderInView;
        await moveEntities(
          parentFolder: folderInView,
          profile: profile,
          emit: emit,
        );
      }
    });
  }

  Future<void> loadParentFolder({
    required FolderWithContents folderInView,
    required Emitter<FsEntryMoveState> emit,
  }) async {
    final parentFolder = folderInView.folder.parentFolderId;
    if (parentFolder != null) {
      return loadFolder(folderId: parentFolder, emit: emit);
    }
  }

  Future<void> loadFolder({
    required String folderId,
    required Emitter<FsEntryMoveState> emit,
  }) async {
    unawaited(_folderSubscription?.cancel());

    _folderSubscription =
        _driveDao.watchFolderContents(driveId, folderId: folderId).listen(
      (f) {
        emit(
          FsEntryMoveLoadSuccess(
            viewingRootFolder: f.folder.parentFolderId == null,
            viewingFolder: f,
            itemsToMove: selectedItems,
          ),
        );
      },
    );
  }

  Future<void> checkForConflicts({
    required final FolderEntry parentFolder,
    required ProfileLoggedIn profile,
    required Emitter<FsEntryMoveState> emit,
  }) async {
    final conflictingItems = <SelectedItem>[];
    try {
      if (await _profileCubit.logoutIfWalletMismatch()) {
        emit(const FsEntryMoveWalletMismatch());
        return;
      }

      for (var itemToMove in selectedItems) {
        final entityWithSameNameExists =
            await _driveDao.doesEntityWithNameExist(
          name: itemToMove.item.name,
          driveId: driveId,
          parentFolderId: parentFolder.id,
        );

        if (entityWithSameNameExists) {
          conflictingItems.add(itemToMove);
        }
      }
      if (conflictingItems.isEmpty) {
        moveEntities(
          conflictingItems: conflictingItems,
          profile: profile,
          parentFolder: parentFolder,
          emit: emit,
        );
      }
    } catch (err) {
      addError(err);
    }
  }

  Future<void> moveEntities({
    required FolderEntry parentFolder,
    List<SelectedItem> conflictingItems = const [],
    required ProfileLoggedIn profile,
    required Emitter<FsEntryMoveState> emit,
  }) async {
    final driveKey = await _driveDao.getDriveKey(driveId, profile.cipherKey);
    final moveTxDataItems = <DataItem>[];

    final filesToMove = selectedItems
        .whereType<SelectedFile>()
        .where((file) => conflictingItems
            .where((conflictingFile) => conflictingFile.id == file.id)
            .isEmpty)
        .toList();

    final foldersToMove = selectedItems
        .whereType<SelectedFolder>()
        .where((folder) => conflictingItems
            .where((conflictingFolder) => conflictingFolder.id == folder.id)
            .isEmpty)
        .toList();

    final folderMap = <String, FolderEntriesCompanion>{};

    await _driveDao.transaction(() async {
      for (var fileToMove in filesToMove) {
        var file = await _driveDao
            .fileById(driveId: driveId, fileId: fileToMove.id)
            .getSingle();
        file = file.copyWith(
            parentFolderId: parentFolder.id,
            path: '${parentFolder.path}/${file.name}',
            lastUpdated: DateTime.now());
        final fileKey =
            driveKey != null ? await deriveFileKey(driveKey, file.id) : null;

        final fileEntity = file.asEntity();

        final fileDataItem = await _arweave.prepareEntityDataItem(
          fileEntity,
          profile.wallet,
          fileKey,
        );
        moveTxDataItems.add(fileDataItem);

        await _driveDao.writeToFile(file);
        fileEntity.txId = fileDataItem.id;

        await _driveDao.insertFileRevision(fileEntity.toRevisionCompanion(
          performedAction: RevisionAction.move,
        ));
      }
      for (var folderToMove in foldersToMove) {
        var folder = await _driveDao
            .folderById(driveId: driveId, folderId: folderToMove.id)
            .getSingle();
        folder = folder.copyWith(
          parentFolderId: parentFolder.id,
          path: '${parentFolder.path}/${folder.name}',
          lastUpdated: DateTime.now(),
        );

        final folderEntity = folder.asEntity();

        final folderDataItem = await _arweave.prepareEntityDataItem(
          folderEntity,
          profile.wallet,
          driveKey,
        );

        await _driveDao.writeToFolder(folder);
        folderEntity.txId = folderDataItem.id;
        await _driveDao.insertFolderRevision(folderEntity.toRevisionCompanion(
          performedAction: RevisionAction.move,
        ));
        folderMap.addAll({folder.id: folder.toCompanion(false)});
      }
    });

    final moveTx = await _arweave.prepareDataBundleTx(
      await DataBundle.fromDataItems(
        items: moveTxDataItems,
      ),
      profile.wallet,
    );
    await _arweave.postTx(moveTx);

    await _syncCubit.generateFsEntryPaths(driveId, folderMap, {});
  }

  @override
  Future<void> close() {
    _folderSubscription?.cancel();
    return super.close();
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    super.onError(error, stackTrace);
  }
}
