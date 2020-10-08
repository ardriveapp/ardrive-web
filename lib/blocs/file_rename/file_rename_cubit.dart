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

  final String _driveId;
  final String _fileId;

  final DriveDao _driveDao;

  FileRenameCubit({
    @required String driveId,
    @required String fileId,
    @required DriveDao driveDao,
  })  : _driveId = driveId,
        _fileId = fileId,
        _driveDao = driveDao,
        super(FileRenameInitial());

  Future<void> submit() async {
    if (form.invalid) {
      return;
    }

    emit(FileRenameInProgress());

    final String fileName = form.control('name').value;

    await _driveDao.renameFile(
      driveId: _driveId,
      fileId: _fileId,
      name: fileName,
    );

    emit(FileRenameSuccess());
  }
}
