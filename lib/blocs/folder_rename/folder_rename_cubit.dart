import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:reactive_forms/reactive_forms.dart';

part 'folder_rename_state.dart';

class FolderRenameCubit extends Cubit<FolderRenameState> {
  final form = FormGroup({
    'name': FormControl(validators: [Validators.required]),
  });

  final String driveId;
  final String folderId;

  final ArweaveService _arweave;
  final DriveDao _driveDao;
  final ProfileBloc _profileBloc;

  FolderRenameCubit({
    @required this.driveId,
    @required this.folderId,
    @required ArweaveService arweave,
    @required DriveDao driveDao,
    @required ProfileBloc profileBloc,
  })  : _arweave = arweave,
        _driveDao = driveDao,
        _profileBloc = profileBloc,
        super(FolderRenameInitializing()) {
    _driveDao.getFolderNameById(driveId, folderId).then(
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
    final profile = _profileBloc.state as ProfileLoaded;

    await _driveDao.transaction(() async {
      var folder = await _driveDao.getFolderById(driveId, folderId);
      final driveKey =
          await _driveDao.getDriveKey(folder.driveId, profile.cipherKey);

      folder = folder.copyWith(name: folderName);

      final folderTx = await _arweave.prepareEntityTx(
        folder.asEntity(),
        profile.wallet,
        driveKey,
      );

      await _arweave.postTx(folderTx);

      await _driveDao.updateFolder(folder);
    });

    emit(FolderRenameSuccess());
  }
}
