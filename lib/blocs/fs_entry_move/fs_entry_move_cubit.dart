import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:moor/moor.dart';
import 'package:pedantic/pedantic.dart';

part 'fs_entry_move_state.dart';

class FsEntryMoveCubit extends Cubit<FsEntryMoveState> {
  final String driveId;
  final String folderId;
  final String fileId;

  final ArweaveService _arweave;
  final DriveDao _driveDao;
  final ProfileCubit _profileCubit;
  final SyncCubit _syncCubit;

  StreamSubscription _folderSubscription;

  bool get _isMovingFolder => folderId != null;

  FsEntryMoveCubit({
    @required this.driveId,
    this.folderId,
    this.fileId,
    @required ArweaveService arweave,
    @required DriveDao driveDao,
    @required ProfileCubit profileCubit,
    @required SyncCubit syncCubit,
  })  : _arweave = arweave,
        _driveDao = driveDao,
        _profileCubit = profileCubit,
        _syncCubit = syncCubit,
        assert(folderId != null || fileId != null),
        super(
            FsEntryMoveFolderLoadInProgress(isMovingFolder: folderId != null)) {
    _driveDao
        .driveById(driveId: driveId)
        .getSingle()
        .then((d) => loadFolder(d.rootFolderId));
  }

  Future<void> loadParentFolder() {
    final state = this.state as FsEntryMoveFolderLoadSuccess;
    return loadFolder(state.viewingFolder.folder.parentFolderId);
  }

  Future<void> loadFolder(String folderId) async {
    unawaited(_folderSubscription?.cancel());

    _folderSubscription =
        _driveDao.watchFolderContents(driveId, folderId: folderId).listen(
              (f) => emit(
                FsEntryMoveFolderLoadSuccess(
                  viewingRootFolder: f.folder.parentFolderId == null,
                  viewingFolder: f,
                  isMovingFolder: _isMovingFolder,
                  movingEntryId: this.folderId ?? fileId,
                ),
              ),
            );
  }

  Future<void> submit() async {
    try {
      final state = this.state as FsEntryMoveFolderLoadSuccess;
      final profile = _profileCubit.state as ProfileLoggedIn;

      final parentFolder = state.viewingFolder.folder;
      final driveKey = await _driveDao.getDriveKey(driveId, profile.cipherKey);

      if (_isMovingFolder) {
        emit(FolderEntryMoveInProgress());

        await _driveDao.transaction(() async {
          var folder = await _driveDao
              .folderById(driveId: driveId, folderId: folderId)
              .getSingle();
          folder = folder.copyWith(
              parentFolderId: parentFolder.id,
              path: '${parentFolder.path}/${folder.name}',
              lastUpdated: DateTime.now());

          final folderEntity = folder.asEntity();

          final folderTx = await _arweave.prepareEntityTx(
              folderEntity, profile.wallet, driveKey);

          await _arweave.postTx(folderTx);
          await _driveDao.writeToFolder(folder);

          folderEntity.txId = folderTx.id;

          await _driveDao.insertFolderRevision(folderEntity.toRevisionCompanion(
              performedAction: RevisionAction.move));

          final folderMap = {folder.id: folder.toCompanion(false)};
          await _syncCubit.generateFsEntryPaths(driveId, folderMap, {});
        });

        emit(FolderEntryMoveSuccess());
      } else {
        emit(FileEntryMoveInProgress());

        await _driveDao.transaction(() async {
          var file = await _driveDao
              .fileById(driveId: driveId, fileId: fileId)
              .getSingle();
          file = file.copyWith(
              parentFolderId: parentFolder.id,
              path: '${parentFolder.path}/${file.name}',
              lastUpdated: DateTime.now());

          final fileKey =
              driveKey != null ? await deriveFileKey(driveKey, file.id) : null;

          final fileEntity = file.asEntity();

          final fileTx = await _arweave.prepareEntityTx(
              fileEntity, profile.wallet, fileKey);

          await _arweave.postTx(fileTx);
          await _driveDao.writeToFile(file);

          fileEntity.txId = fileTx.id;

          await _driveDao.insertFileRevision(fileEntity.toRevisionCompanion(
              performedAction: RevisionAction.move));
        });

        emit(FileEntryMoveSuccess());
      }
    } catch (err) {
      addError(err);
    }
  }

  @override
  Future<void> close() {
    _folderSubscription?.cancel();
    return super.close();
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    if (_isMovingFolder) {
      emit(FolderEntryMoveFailure());
    } else {
      emit(FileEntryMoveFailure());
    }

    super.onError(error, stackTrace);
  }
}
