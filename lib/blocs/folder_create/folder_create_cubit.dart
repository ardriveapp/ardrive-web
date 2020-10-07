import 'package:bloc/bloc.dart';
import 'package:drive/blocs/blocs.dart';
import 'package:drive/entities/entities.dart';
import 'package:drive/models/models.dart';
import 'package:drive/services/services.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:reactive_forms/reactive_forms.dart';

part 'folder_create_state.dart';

class FolderCreateCubit extends Cubit<FolderCreateState> {
  final form = FormGroup({
    'name': FormControl(validators: [Validators.required]),
  });

  final DriveDetailCubit _driveDetailCubit;
  final ProfileBloc _profileBloc;

  final ArweaveService _arweave;
  final DriveDao _driveDao;

  FolderCreateCubit({
    @required DriveDetailCubit driveDetailCubit,
    @required ProfileBloc profileBloc,
    @required ArweaveService arweave,
    @required DriveDao driveDao,
  })  : _driveDetailCubit = driveDetailCubit,
        _profileBloc = profileBloc,
        _arweave = arweave,
        _driveDao = driveDao,
        super(FolderCreateInitial());

  Future<void> submit() async {
    if (form.invalid) {
      return;
    }

    emit(FolderCreateInProgress());

    final profile = _profileBloc.state as ProfileLoaded;
    final driveState = _driveDetailCubit.state as FolderLoadSuccess;

    final currentDrive = driveState.currentDrive;
    final currentFolder = driveState.currentFolder.folder;

    final String folderName = form.control('name').value;

    final driveKey = driveState.currentDrive.isPrivate
        ? await _driveDao.getDriveKey(currentDrive.id, profile.cipherKey)
        : null;

    final newFolderId = await _driveDao.createFolder(
      driveId: currentDrive.id,
      parentFolderId: currentFolder.id,
      folderName: folderName,
      path: '${currentFolder.path}/${folderName}',
    );

    final folderTx = await _arweave.prepareEntityTx(
      FolderEntity(
        id: newFolderId,
        driveId: currentFolder.driveId,
        parentFolderId: currentFolder.id,
        name: folderName,
      ),
      profile.wallet,
      driveKey,
    );

    await _arweave.postTx(folderTx);

    emit(FolderCreateSuccess());
  }
}
