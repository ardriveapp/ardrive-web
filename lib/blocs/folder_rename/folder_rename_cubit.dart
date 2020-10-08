import 'package:ardrive/models/models.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:reactive_forms/reactive_forms.dart';

part 'folder_rename_state.dart';

class FolderRenameCubit extends Cubit<FolderRenameState> {
  final form = FormGroup({
    'name': FormControl(validators: [Validators.required]),
  });

  final String folderId;

  final DriveDao _driveDao;

  FolderRenameCubit({@required this.folderId, @required DriveDao driveDao})
      : _driveDao = driveDao,
        super(FolderRenameInitializing()) {
    _driveDao.getFolderNameById(folderId).then(
      (name) {
        form.control('name').value = name;
        emit(FolderRenameInitialized());
      },
    );
  }

  Future<void> submit() async {
    if (form.invalid) {
      return;
    }

    emit(FolderRenameInProgress());

    final String folderName = form.control('name').value;

    await _driveDao.renameFolder(
      folderId: folderId,
      name: folderName,
    );

    emit(FolderRenameSuccess());
  }
}
