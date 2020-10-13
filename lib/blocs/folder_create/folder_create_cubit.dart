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

  final ProfileBloc _profileBloc;

  final ArweaveService _arweave;
  final DriveDao _driveDao;

  FolderCreateCubit({
    @required this.targetDriveId,
    @required this.targetFolderId,
    @required ProfileBloc profileBloc,
    @required ArweaveService arweave,
    @required DriveDao driveDao,
  })  : _profileBloc = profileBloc,
        _arweave = arweave,
        _driveDao = driveDao,
        super(FolderCreateInitial());

  Future<void> submit() async {
    if (form.invalid) {
      return;
    }

    emit(FolderCreateInProgress());

    final profile = _profileBloc.state as ProfileLoaded;
    final String folderName = form.control('name').value;

    await _driveDao.transaction(() async {
      final targetDrive = await _driveDao.getDriveById(targetDriveId);
      final targetFolder =
          await _driveDao.getFolderById(targetDriveId, targetFolderId);

      final driveKey = targetDrive.isPrivate
          ? await _driveDao.getDriveKey(targetFolder.driveId, profile.cipherKey)
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

    emit(FolderCreateSuccess());
  }
}
