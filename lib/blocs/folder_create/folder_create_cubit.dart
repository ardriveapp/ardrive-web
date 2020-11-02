import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:reactive_forms/reactive_forms.dart';

part 'folder_create_state.dart';

class FolderCreateCubit extends Cubit<FolderCreateState> {
  final form = FormGroup({
    'name': FormControl(validators: [Validators.required]),
  });

  final String targetDriveId;
  final String targetFolderId;

  final ProfileCubit _profileCubit;

  final ArweaveService _arweave;
  final DriveDao _driveDao;

  FolderCreateCubit({
    @required this.targetDriveId,
    @required this.targetFolderId,
    @required ProfileCubit profileCubit,
    @required ArweaveService arweave,
    @required DriveDao driveDao,
  })  : _profileCubit = profileCubit,
        _arweave = arweave,
        _driveDao = driveDao,
        super(FolderCreateInitial());

  Future<void> submit() async {
    form.markAllAsTouched();

    if (form.invalid) {
      return;
    }

    emit(FolderCreateInProgress());

    try {
      final profile = _profileCubit.state as ProfileLoaded;
      final String folderName = form.control('name').value;

      await _driveDao.transaction(() async {
        final targetDrive = await _driveDao.getDriveById(targetDriveId);
        final targetFolder =
            await _driveDao.getFolderById(targetDriveId, targetFolderId);

        final driveKey = targetDrive.isPrivate
            ? await _driveDao.getDriveKey(
                targetFolder.driveId, profile.cipherKey)
            : null;

        final newFolderId = await _driveDao.createFolder(
          driveId: targetFolder.driveId,
          parentFolderId: targetFolder.id,
          folderName: folderName,
          path: '${targetFolder.path}/${folderName}',
        );

        final folderTx = await _arweave.prepareEntityTx(
          FolderEntity(
            id: newFolderId,
            driveId: targetFolder.driveId,
            parentFolderId: targetFolder.id,
            name: folderName,
          ),
          profile.wallet,
          driveKey,
        );

        await _arweave.postTx(folderTx);
      });
    } catch (err) {
      addError(err);
    }

    emit(FolderCreateSuccess());
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(FolderCreateFailure());
    super.onError(error, stackTrace);
  }
}
