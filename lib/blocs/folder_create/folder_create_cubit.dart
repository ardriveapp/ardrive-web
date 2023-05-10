import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'folder_create_state.dart';

class FolderCreateCubit extends Cubit<FolderCreateState> {
  final String driveId;
  final String parentFolderId;

  final ProfileCubit _profileCubit;

  final ArweaveService _arweave;
  final UploadService _turboUploadService;
  final DriveDao _driveDao;

  FolderCreateCubit({
    required this.driveId,
    required this.parentFolderId,
    required ProfileCubit profileCubit,
    required ArweaveService arweave,
    required UploadService turboUploadService,
    required DriveDao driveDao,
  })  : _profileCubit = profileCubit,
        _arweave = arweave,
        _turboUploadService = turboUploadService,
        _driveDao = driveDao,
        super(FolderCreateInitial());

  Future<void> submit({required String folderName}) async {
    try {
      final profile = _profileCubit.state as ProfileLoggedIn;

      if (await _profileCubit.logoutIfWalletMismatch()) {
        emit(FolderCreateWalletMismatch());
        return;
      }

      if (await _nameAlreadyExists(folderName)) {
        emit(FolderCreateNameAlreadyExists(folderName: folderName));

        return;
      }

      emit(FolderCreateInProgress());

      await _driveDao.transaction(() async {
        final targetDrive =
            await _driveDao.driveById(driveId: driveId).getSingle();
        final targetFolder = await _driveDao
            .folderById(driveId: driveId, folderId: parentFolderId)
            .getSingle();

        final driveKey = targetDrive.isPrivate
            ? await _driveDao.getDriveKey(
                targetFolder.driveId, profile.cipherKey)
            : null;

        final newFolderId = await _driveDao.createFolder(
          driveId: targetFolder.driveId,
          parentFolderId: targetFolder.id,
          folderName: folderName,
          path: '${targetFolder.path}/$folderName',
        );

        final folderEntity = FolderEntity(
          id: newFolderId,
          driveId: targetFolder.driveId,
          parentFolderId: targetFolder.id,
          name: folderName,
        );
        if (_turboUploadService.useTurbo) {
          final folderDataItem = await _arweave.prepareEntityDataItem(
            folderEntity,
            profile.wallet,
            key: driveKey,
          );

          await _turboUploadService.postDataItem(dataItem: folderDataItem);
          folderEntity.txId = folderDataItem.id;
        } else {
          final folderTx = await _arweave.prepareEntityTx(
            folderEntity,
            profile.wallet,
            driveKey,
          );

          await _arweave.postTx(folderTx);
          folderEntity.txId = folderTx.id;
        }

        await _driveDao.insertFolderRevision(folderEntity.toRevisionCompanion(
          performedAction: RevisionAction.create,
        ));
      });
    } catch (err) {
      addError(err);
      return;
    }

    emit(FolderCreateSuccess());
  }

  Future<bool> _nameAlreadyExists(String folderName) async {
    final nameAlreadyExists = await _driveDao.doesEntityWithNameExist(
      name: folderName,
      driveId: driveId,
      parentFolderId: parentFolderId,
    );

    return nameAlreadyExists;
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(FolderCreateFailure());
    super.onError(error, stackTrace);

    print('Failed to create folder: $error $stackTrace');
  }
}
