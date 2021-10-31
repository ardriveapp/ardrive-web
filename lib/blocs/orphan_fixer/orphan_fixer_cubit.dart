import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';

part 'orphan_fixer_state.dart';

class OrphanFixerCubit extends Cubit<OrphanFixerState> {
  final String driveId;
  final List<String> folderIds;
  final String parentFolderId;
  final ProfileCubit _profileCubit;

  final ArweaveService _arweave;
  final DriveDao _driveDao;

  OrphanFixerCubit({
    required this.driveId,
    required this.folderIds,
    required this.parentFolderId,
    required ProfileCubit profileCubit,
    required ArweaveService arweave,
    required DriveDao driveDao,
  })  : _profileCubit = profileCubit,
        _arweave = arweave,
        _driveDao = driveDao,
        super(OrphanFixerInitial());

  Future<void> fix() async {
    try {
      final profile = _profileCubit.state as ProfileLoggedIn;
      for (var id in folderIds) {
        final folderName = id;
        if (await _profileCubit.logoutIfWalletMismatch()) {
          emit(OrphanFixerWalletMismatch());
          return;
        }
        emit(OrphanFixerInProgress());

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

          final folderTx = await _arweave.prepareEntityTx(
            folderEntity,
            profile.wallet,
            driveKey,
          );

          await _arweave.postTx(folderTx);
          folderEntity.txId = folderTx.id;
          await _driveDao.insertFolderRevision(folderEntity.toRevisionCompanion(
              performedAction: RevisionAction.create));
        });
      }
    } catch (err) {
      addError(err);
    }

    emit(OrphanFixerSuccess());
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(OrphanFixerFailure());
    super.onError(error, stackTrace);

    print('Failed to create folders: $error $stackTrace');
  }
}
