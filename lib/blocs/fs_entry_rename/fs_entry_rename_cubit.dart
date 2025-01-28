import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:drift/drift.dart';
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
  final TurboUploadService _turboUploadService;
  final DriveDao _driveDao;
  final ProfileCubit _profileCubit;
  final ArDriveCrypto _crypto;

  bool get _isRenamingFolder => folderId != null;

  bool _dontVerifyExtension = false;

  FsEntryRenameCubit({
    required this.driveId,
    this.folderId,
    this.fileId,
    required ArweaveService arweave,
    required TurboUploadService turboUploadService,
    required DriveDao driveDao,
    required ProfileCubit profileCubit,
    required ArDriveCrypto crypto,
  })  : _arweave = arweave,
        _turboUploadService = turboUploadService,
        _driveDao = driveDao,
        _profileCubit = profileCubit,
        _crypto = crypto,
        assert(folderId != null || fileId != null),
        super(FsEntryRenameInitializing(isRenamingFolder: folderId != null)) {
    emit(FsEntryRenameInitialized(isRenamingFolder: _isRenamingFolder));
  }

  Future<void> reset() async {
    emit(FsEntryRenameInitialized(isRenamingFolder: _isRenamingFolder));
  }

  Future<void> submit({
    required String newName,
    bool updateExtension = false,
  }) async {
    try {
      final bool hasEntityWithSameName;

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
      final driveKey =
          await _driveDao.getDriveKey(driveId, profile.user.cipherKey);

      if (await _profileCubit.logoutIfWalletMismatch()) {
        emit(_isRenamingFolder
            ? const FolderEntryRenameWalletMismatch()
            : const FileEntryRenameWalletMismatch());
        return;
      }

      if (_isRenamingFolder) {
        emit(const FolderEntryRenameInProgress());
        var folder =
            await _driveDao.folderById(folderId: folderId!).getSingle();
        folder = folder.copyWith(name: newName, lastUpdated: DateTime.now());

        await _driveDao.transaction(() async {
          final folderEntity = folder.asEntity();
          if (_turboUploadService.useTurboUpload) {
            final folderDataItem = await _arweave.prepareEntityDataItem(
              folderEntity,
              profile.user.wallet,
              key: driveKey,
            );

            await _turboUploadService.postDataItem(
              dataItem: folderDataItem,
              wallet: profile.user.wallet,
            );
            folderEntity.txId = folderDataItem.id;
          } else {
            final folderTx = await _arweave.prepareEntityTx(
                folderEntity, profile.user.wallet, driveKey);

            await _arweave.postTx(folderTx);
            folderEntity.txId = folderTx.id;
          }

          await _driveDao.writeToFolder(folder);

          await _driveDao.insertFolderRevision(folderEntity.toRevisionCompanion(
              performedAction: RevisionAction.rename));
        });

        emit(const FolderEntryRenameSuccess());
      } else {
        var file = await _driveDao.fileById(fileId: fileId!).getSingle();

        if (!updateExtension && !_dontVerifyExtension) {
          final newFileExtension =
              getFileExtensionFromFileName(fileName: newName);

          if (newFileExtension.isNotEmpty) {
            bool hasExtensionChanged;

            final currentExtension = getFileExtension(
                name: file.name, contentType: file.dataContentType!);

            hasExtensionChanged = currentExtension != newFileExtension;

            if (hasExtensionChanged) {
              emit(
                UpdatingEntityExtension(
                  previousExtension: currentExtension,
                  entityName: newName,
                  newExtension: newFileExtension,
                ),
              );

              return;
            }
          }
        }

        emit(const FileEntryRenameInProgress());

        await _driveDao.transaction(() async {
          file = file.copyWith(
            name: newName,
            lastUpdated: DateTime.now(),
          );

          if (updateExtension) {
            file =
                file.copyWith(dataContentType: Value(lookupMimeType(newName)));
          }

          final fileKey = driveKey != null
              ? await _crypto.deriveFileKey(driveKey, file.id)
              : null;

          final fileEntity = file.asEntity();

          if (_turboUploadService.useTurboUpload) {
            final fileDataItem = await _arweave.prepareEntityDataItem(
              fileEntity,
              profile.user.wallet,
              key: fileKey,
            );

            await _turboUploadService.postDataItem(
              dataItem: fileDataItem,
              wallet: profile.user.wallet,
            );
            fileEntity.txId = fileDataItem.id;
          } else {
            final fileTx = await _arweave.prepareEntityTx(
                fileEntity, profile.user.wallet, fileKey);

            await _arweave.postTx(fileTx);
            fileEntity.txId = fileTx.id;
          }

          logger.i(
              'Updating file ${file.id} with txId ${fileEntity.txId}. Data content type: ${fileEntity.dataContentType}');

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
    final folder = await _driveDao.folderById(folderId: folderId!).getSingle();
    final entityWithSameNameExists = await _driveDao.doesEntityWithNameExist(
      name: newFolderName,
      driveId: driveId,
      // Will never be null since you can't rename root folder
      parentFolderId: folder.parentFolderId!,
    );

    return entityWithSameNameExists;
  }

  Future<bool> _fileWithSameNameExistis(String newFileName) async {
    final file = await _driveDao.fileById(fileId: fileId!).getSingle();

    final entityWithSameNameExists = await _driveDao.doesEntityWithNameExist(
      name: newFileName,
      driveId: driveId,
      parentFolderId: file.parentFolderId,
    );

    return entityWithSameNameExists;
  }

  void dontVerifyExtension() {
    _dontVerifyExtension = true;
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    if (_isRenamingFolder) {
      emit(const FolderEntryRenameFailure());
      logger.e('Failed to rename folder', error, stackTrace);
    } else {
      emit(const FileEntryRenameFailure());
      logger.e('Failed to rename file', error, stackTrace);
    }

    super.onError(error, stackTrace);
  }
}
