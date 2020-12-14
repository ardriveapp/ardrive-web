import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:reactive_forms/reactive_forms.dart';

part 'fs_entry_rename_state.dart';

class FsEntryRenameCubit extends Cubit<FsEntryRenameState> {
  final form;

  final String driveId;
  final String folderId;
  final String fileId;

  final ArweaveService _arweave;
  final DriveDao _driveDao;
  final ProfileCubit _profileCubit;

  bool get _isRenamingFolder => folderId != null;

  FsEntryRenameCubit({
    @required this.driveId,
    this.folderId,
    this.fileId,
    @required ArweaveService arweave,
    @required DriveDao driveDao,
    @required ProfileCubit profileCubit,
  })  : form = FormGroup({
          'name': FormControl(
            validators: [
              Validators.required,
              Validators.pattern(
                  folderId != null ? kFolderNameRegex : kFileNameRegex),
            ],
          ),
        }),
        _arweave = arweave,
        _driveDao = driveDao,
        _profileCubit = profileCubit,
        assert(folderId != null || fileId != null),
        super(FsEntryRenameInitializing(isRenamingFolder: folderId != null)) {
    () async {
      final name = _isRenamingFolder
          ? await _driveDao
              .selectFolderById(driveId, folderId)
              .map((f) => f.name)
              .getSingle()
          : await _driveDao
              .selectFileById(driveId, fileId)
              .map((f) => f.name)
              .getSingle();

      form.control('name').value = name;
      emit(FsEntryRenameInitialized(isRenamingFolder: _isRenamingFolder));
    }();
  }

  Future<void> submit() async {
    form.markAllAsTouched();

    if (form.invalid) {
      return;
    }

    try {
      final String newName = form.control('name').value;
      final profile = _profileCubit.state as ProfileLoaded;
      final driveKey = await _driveDao.getDriveKey(driveId, profile.cipherKey);

      if (_isRenamingFolder) {
        emit(FolderEntryRenameInProgress());

        await _driveDao.transaction(() async {
          var folder = await _driveDao.getFolderById(driveId, folderId);
          folder = folder.copyWith(name: newName, lastUpdated: DateTime.now());

          final folderTx = await _arweave.prepareEntityTx(
              folder.asEntity(), profile.wallet, driveKey);

          await _arweave.postTx(folderTx);
          await _driveDao.writeToFolder(folder);
        });

        emit(FolderEntryRenameSuccess());
      } else {
        emit(FileEntryRenameInProgress());

        await _driveDao.transaction(() async {
          var file = await _driveDao.getFileById(driveId, fileId);
          file = file.copyWith(name: newName, lastUpdated: DateTime.now());

          final fileKey =
              driveKey != null ? await deriveFileKey(driveKey, file.id) : null;

          final fileTx = await _arweave.prepareEntityTx(
              file.asEntity(), profile.wallet, fileKey);

          await _arweave.postTx(fileTx);
          await _driveDao.writeToFile(file);
        });

        emit(FileEntryRenameSuccess());
      }
    } catch (err) {
      addError(err);
    }
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    if (_isRenamingFolder) {
      emit(FolderEntryRenameFailure());
    } else {
      emit(FileEntryRenameFailure());
    }

    super.onError(error, stackTrace);
  }
}
