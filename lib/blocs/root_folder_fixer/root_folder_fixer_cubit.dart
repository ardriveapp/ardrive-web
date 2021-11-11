import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';

part 'root_folder_fixer_state.dart';

class RootFolderFixerCubit extends Cubit<RootFolderFixerState> {
  final OrphanParent orphanParent;
  final ProfileCubit _profileCubit;

  final ArweaveService _arweave;
  final DriveDao _driveDao;

  RootFolderFixerCubit({
    required this.orphanParent,
    required ProfileCubit profileCubit,
    required ArweaveService arweave,
    required DriveDao driveDao,
  })  : _profileCubit = profileCubit,
        _arweave = arweave,
        _driveDao = driveDao,
        super(RootFolderFixerInitial());

  Future<void> submit() async {
    try {
      final profile = _profileCubit.state as ProfileLoggedIn;
      if (await _profileCubit.logoutIfWalletMismatch()) {
        emit(RootFolderFixerWalletMismatch());
        return;
      }
      emit(RootFolderFixerInProgress());

      await _driveDao.transaction(() async {
        final targetDrive = await _driveDao
            .driveById(driveId: orphanParent.driveId)
            .getSingle();

        final driveKey = targetDrive.isPrivate
            ? await _driveDao.getDriveKey(targetDrive.id, profile.cipherKey)
            : null;
        final rootFolderEntity = FolderEntity(
          id: targetDrive.rootFolderId,
          driveId: targetDrive.id,
          name: targetDrive.name,
        );
        final rootFolderTx = await _arweave.prepareEntityTx(
          rootFolderEntity,
          profile.wallet,
          driveKey,
        );

        await _arweave.postTx(rootFolderTx);
        rootFolderEntity.txId = rootFolderTx.id;
        await _driveDao.insertFolderRevision(rootFolderEntity
            .toRevisionCompanion(performedAction: RevisionAction.create));
      });
    } catch (err) {
      addError(err);
    }

    emit(RootFolderFixerSuccess());
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(RootFolderFixerFailure());
    super.onError(error, stackTrace);

    print('Failed to create folder: $error $stackTrace');
  }
}
