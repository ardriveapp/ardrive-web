import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/l11n/validation_messages.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:reactive_forms/reactive_forms.dart';

part 'fs_entry_rename_state.dart';

class FsEntryRenameCubit extends Cubit<FsEntryRenameState> {
  late FormGroup form;

  final String driveId;
  final String? folderId;
  final String? fileId;

  final ArweaveService _arweave;
  final DriveDao _driveDao;
  final ProfileCubit _profileCubit;
  final SyncCubit _syncCubit;

  bool get _isRenamingFolder => folderId != null;

  FsEntryRenameCubit({
    required this.driveId,
    this.folderId,
    this.fileId,
    required ArweaveService arweave,
    required DriveDao driveDao,
    required ProfileCubit profileCubit,
    required SyncCubit syncCubit,
  })  : _arweave = arweave,
        _driveDao = driveDao,
        _profileCubit = profileCubit,
        _syncCubit = syncCubit,
        assert(folderId != null || fileId != null),
        super(FsEntryRenameInitializing(isRenamingFolder: folderId != null)) {
    form = FormGroup({
      'name': FormControl<String>(
        validators: [
          Validators.required,
          Validators.pattern(
              folderId != null ? kFolderNameRegex : kFileNameRegex),
          Validators.pattern(kTrimTrailingRegex),
        ],
        asyncValidators: [
          folderId != null ? _uniqueFolderName : _uniqueFileName,
        ],
      ),
    });

    () async {
      final name = _isRenamingFolder
          ? await _driveDao
              .folderById(driveId: driveId, folderId: folderId!)
              .map((f) => f.name)
              .getSingle()
          : await _driveDao
              .fileById(driveId: driveId, fileId: fileId!)
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
      final newName = form.control('name').value.toString().trim();
      final profile = _profileCubit.state as ProfileLoggedIn;
      final driveKey = await _driveDao.getDriveKey(driveId, profile.cipherKey);

      if (await _profileCubit.logoutIfWalletMismatch()) {
        emit(_isRenamingFolder
            ? const FolderEntryRenameWalletMismatch()
            : const FileEntryRenameWalletMismatch());
        return;
      }
      if (_isRenamingFolder) {
        emit(const FolderEntryRenameInProgress());

        await _driveDao.transaction(() async {
          var folder = await _driveDao
              .folderById(driveId: driveId, folderId: folderId!)
              .getSingle();
          folder = folder.copyWith(name: newName, lastUpdated: DateTime.now());

          final folderEntity = folder.asEntity();
          final folderTx = await _arweave.prepareEntityTx(
              folderEntity, profile.wallet, driveKey);

          await _arweave.postTx(folderTx);
          await _driveDao.writeToFolder(folder);
          folderEntity.txId = folderTx.id;

          await _driveDao.insertFolderRevision(folderEntity.toRevisionCompanion(
              performedAction: RevisionAction.rename));

          final folderMap = {folder.id: folder.toCompanion(false)};
          await _syncCubit.generateFsEntryPaths(driveId, folderMap, {});
        });

        emit(const FolderEntryRenameSuccess());
      } else {
        emit(const FileEntryRenameInProgress());

        await _driveDao.transaction(() async {
          var file = await _driveDao
              .fileById(driveId: driveId, fileId: fileId!)
              .getSingle();
          file = file.copyWith(name: newName, lastUpdated: DateTime.now());

          final fileKey =
              driveKey != null ? await deriveFileKey(driveKey, file.id) : null;

          final fileEntity = file.asEntity();
          final fileTx = await _arweave.prepareEntityTx(
              fileEntity, profile.wallet, fileKey);

          await _arweave.postTx(fileTx);
          await _driveDao.writeToFile(file);

          fileEntity.txId = fileTx.id;

          await _driveDao.insertFileRevision(fileEntity.toRevisionCompanion(
              performedAction: RevisionAction.rename));
        });

        emit(const FileEntryRenameSuccess());
      }
    } catch (err) {
      addError(err);
    }
  }

  Future<Map<String, dynamic>?> _uniqueFolderName(
      AbstractControl<dynamic> control) async {
    final folder = await _driveDao
        .folderById(driveId: driveId, folderId: folderId!)
        .getSingle();
    final String newFolderName = control.value;

    if (newFolderName == folder.name) {
      control.markAsTouched();
      return {AppValidationMessage.fsEntryNameUnchanged: true};
    }

    final entityWithSameNameExists = await _driveDao.doesEntityWithNameExist(
      name: newFolderName,
      driveId: driveId,
      // Will never be null since you can't rename root folder
      parentFolderId: folder.parentFolderId!,
    );

    if (entityWithSameNameExists) {
      control.markAsTouched();
      return {AppValidationMessage.fsEntryNameAlreadyPresent: true};
    }

    return null;
  }

  Future<Map<String, dynamic>?> _uniqueFileName(
      AbstractControl<dynamic> control) async {
    final file =
        await _driveDao.fileById(driveId: driveId, fileId: fileId!).getSingle();
    final String newFileName = control.value;

    if (newFileName == file.name) {
      control.markAsTouched();
      return {AppValidationMessage.fsEntryNameUnchanged: true};
    }

    final entityWithSameNameExists = await _driveDao.doesEntityWithNameExist(
      name: newFileName,
      driveId: driveId,
      parentFolderId: file.parentFolderId,
    );

    if (entityWithSameNameExists) {
      control.markAsTouched();
      return {AppValidationMessage.fsEntryNameAlreadyPresent: true};
    }

    return null;
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    if (_isRenamingFolder) {
      emit(const FolderEntryRenameFailure());
      print('Failed to rename folder: $error $stackTrace');
    } else {
      emit(const FileEntryRenameFailure());
      print('Failed to rename file: $error $stackTrace');
    }

    super.onError(error, stackTrace);
  }
}
