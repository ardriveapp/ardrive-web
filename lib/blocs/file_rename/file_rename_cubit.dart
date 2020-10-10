import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
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

  final ArweaveService _arweave;
  final DriveDao _driveDao;
  final ProfileBloc _profileBloc;

  FileRenameCubit({
    @required this.fileId,
    @required ArweaveService arweave,
    @required DriveDao driveDao,
    @required ProfileBloc profileBloc,
  })  : _arweave = arweave,
        _driveDao = driveDao,
        _profileBloc = profileBloc,
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
    final profile = _profileBloc.state as ProfileLoaded;

    final file = await _driveDao.getFileById(fileId);
    final driveKey =
        await _driveDao.getDriveKey(file.driveId, profile.cipherKey);

    final renamedFile = file.copyWith(name: fileName);

    final folderTx = await _arweave.prepareEntityTx(
      renamedFile.asEntity(),
      profile.wallet,
      driveKey,
    );

    await _arweave.postTx(folderTx);

    await _driveDao.updateFile(renamedFile);

    emit(FileRenameSuccess());
  }
}
