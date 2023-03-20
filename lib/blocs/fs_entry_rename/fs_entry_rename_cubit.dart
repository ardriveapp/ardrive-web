import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

part 'fs_entry_rename_state.dart';

class FsEntryRenameCubit extends Cubit<FsEntryRenameState> {
  late FormGroup form;

  final String driveId;
  final String? folderId;
  final String? fileId;

  final ArweaveService _arweave;
  final TurboService _turboService;
  final DriveDao _driveDao;
  final ProfileCubit _profileCubit;
  final SyncCubit _syncCubit;
  final ArDriveCrypto _crypto;

  bool get _isRenamingFolder => folderId != null;

  FsEntryRenameCubit({
    required this.driveId,
    this.folderId,
    this.fileId,
    required ArweaveService arweave,
    required TurboService turboService,
    required DriveDao driveDao,
    required ProfileCubit profileCubit,
    required SyncCubit syncCubit,
    required ArDriveCrypto crypto,
  })  : _arweave = arweave,
        _turboService = turboService,
        _driveDao = driveDao,
        _profileCubit = profileCubit,
        _syncCubit = syncCubit,
        _crypto = crypto,
        assert(folderId != null || fileId != null),
        super(FsEntryRenameInitializing(isRenamingFolder: folderId != null)) {
    emit(FsEntryRenameInitialized(isRenamingFolder: _isRenamingFolder));
  }

  Future<void> submit({required String newName}) async {
    try {
      late bool hasEntityWithSameName;

      if (_isRenamingFolder) {
        hasEntityWithSameName = await _folderWithSameNameExists(newName);
      } else {
        hasEntityWithSameName = await _fileWithSameNameExistis(newName);
      }

      if (hasEntityWithSameName) {
        final previousState = state;
        emit(EntityAlreadyExists(newName, isRenamingFolder: _isRenamingFolder));
        emit(previousState);
        return;
      }

      final profile = _profileCubit.state as ProfileLoggedIn;
      final driveKey = await _driveDao.getDriveKey(driveId, profile.cipherKey);

      if (await _profileCubit.logoutIfWalletMismatch()) {
        emit(_isRenamingFolder
            ? const FolderEntryRenameWalletMismatch()
            : const FileEntryRenameWalletMismatch());
        return;
      }

      if (_isRenamingFolder) {
        emit(const FolderEntryRenameInProgress());

        await _driveDao.transaction(() async {
          var folder = await _driveDao
              .folderById(driveId: driveId, folderId: folderId!)
              .getSingle();
          folder = folder.copyWith(name: newName, lastUpdated: DateTime.now());

          final folderEntity = folder.asEntity();
          if (_turboService.useTurbo) {
            final folderDataItem = await _arweave.prepareEntityDataItem(
              folderEntity,
              profile.wallet,
              key: driveKey,
            );

            await _turboService.postDataItem(dataItem: folderDataItem);
            folderEntity.txId = folderDataItem.id;
          } else {
            final folderTx = await _arweave.prepareEntityTx(
                folderEntity, profile.wallet, driveKey);

            await _arweave.postTx(folderTx);
            folderEntity.txId = folderTx.id;
          }

          await _driveDao.writeToFolder(folder);

          await _driveDao.insertFolderRevision(folderEntity.toRevisionCompanion(
              performedAction: RevisionAction.rename));

          final folderMap = {folder.id: folder.toCompanion(false)};
          await _syncCubit.generateFsEntryPaths(driveId, folderMap, {});
        });

        emit(const FolderEntryRenameSuccess());
      } else {
        emit(const FileEntryRenameInProgress());

        await _driveDao.transaction(() async {
          var file = await _driveDao
              .fileById(driveId: driveId, fileId: fileId!)
              .getSingle();
          file = file.copyWith(name: newName, lastUpdated: DateTime.now());

          final fileKey = driveKey != null
              ? await _crypto.deriveFileKey(driveKey, file.id)
              : null;

          final fileEntity = file.asEntity();

          if (_turboService.useTurbo) {
            final fileDataItem = await _arweave.prepareEntityDataItem(
              fileEntity,
              profile.wallet,
              key: fileKey,
            );

            await _turboService.postDataItem(dataItem: fileDataItem);
            fileEntity.txId = fileDataItem.id;
          } else {
            final fileTx = await _arweave.prepareEntityTx(
                fileEntity, profile.wallet, fileKey);

            await _arweave.postTx(fileTx);
            fileEntity.txId = fileTx.id;
          }

          await _driveDao.writeToFile(file);

          await _driveDao.insertFileRevision(fileEntity.toRevisionCompanion(
              performedAction: RevisionAction.rename));
        });

        emit(const FileEntryRenameSuccess());
      }
    } catch (err) {
      addError(err);
    }
  }

  Future<bool> _folderWithSameNameExists(String newFolderName) async {
    final folder = await _driveDao
        .folderById(driveId: driveId, folderId: folderId!)
        .getSingle();
    final entityWithSameNameExists = await _driveDao.doesEntityWithNameExist(
      name: newFolderName,
      driveId: driveId,
      // Will never be null since you can't rename root folder
      parentFolderId: folder.parentFolderId!,
    );

    return entityWithSameNameExists;
  }

  Future<bool> _fileWithSameNameExistis(String newFileName) async {
    final file =
        await _driveDao.fileById(driveId: driveId, fileId: fileId!).getSingle();

    final entityWithSameNameExists = await _driveDao.doesEntityWithNameExist(
      name: newFileName,
      driveId: driveId,
      parentFolderId: file.parentFolderId,
    );

    return entityWithSameNameExists;
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    if (_isRenamingFolder) {
      emit(const FolderEntryRenameFailure());
      print('Failed to rename folder: $error $stackTrace');
    } else {
      emit(const FileEntryRenameFailure());
      print('Failed to rename file: $error $stackTrace');
    }

    super.onError(error, stackTrace);
  }
}
