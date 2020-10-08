import 'package:ardrive/models/models.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:reactive_forms/reactive_forms.dart';

part 'file_rename_state.dart';

class FileRenameCubit extends Cubit<FileRenameState> {
  final form = FormGroup({
    'name': FormControl(validators: [Validators.required]),
  });

  final String fileId;

  final DriveDao _driveDao;

  FileRenameCubit({
    @required this.fileId,
    @required DriveDao driveDao,
  })  : _driveDao = driveDao,
        super(FileRenameInitializing()) {
    _driveDao.getFileNameById(fileId).then((name) {
      form.control('name').value = name;
      emit(FileRenameInitialized());
    });
  }

  Future<void> submit() async {
    if (form.invalid) {
      return;
    }

    emit(FileRenameInProgress());

    final String fileName = form.control('name').value;

    await _driveDao.renameFile(
      fileId: fileId,
      name: fileName,
    );

    emit(FileRenameSuccess());
  }
}
