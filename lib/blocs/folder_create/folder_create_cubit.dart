import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:moor/moor.dart';
import 'package:reactive_forms/reactive_forms.dart';

part 'folder_create_state.dart';

class FolderCreateCubit extends Cubit<FolderCreateState> {
  FormGroup form;

  final String driveId;
  final String parentFolderId;

  final ProfileCubit _profileCubit;

  final ArweaveService _arweave;
  final DriveDao _driveDao;

  FolderCreateCubit({
    @required this.driveId,
    @required this.parentFolderId,
    @required ProfileCubit profileCubit,
    @required ArweaveService arweave,
    @required DriveDao driveDao,
  })  : _profileCubit = profileCubit,
        _arweave = arweave,
        _driveDao = driveDao,
        super(FolderCreateInitial()) {
    form = FormGroup({
      'name': FormControl(
        validators: [
          Validators.required,
          Validators.pattern(kFolderNameRegex),
        ],
        asyncValidators: [
          _uniqueFolderName,
        ],
      ),
    });
  }

  Future<void> submit() async {
    form.markAllAsTouched();

    if (form.invalid) {
      return;
    }

    emit(FolderCreateInProgress());

    try {
      final profile = _profileCubit.state as ProfileLoggedIn;
      final String folderName = form.control('name').value;

      await _driveDao.transaction(() async {
        final targetDrive =
            await _driveDao.driveById(driveId: driveId).getSingle();
        final targetFolder = await _driveDao
            .folderById(driveId: driveId, folderId: parentFolderId)
            .getSingle();

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

        final folderEntity = FolderEntity(
          id: newFolderId,
          driveId: targetFolder.driveId,
          parentFolderId: targetFolder.id,
          name: folderName,
        );

        final folderTx = await _arweave.prepareEntityTx(
          folderEntity,
          profile.wallet,
          driveKey,
        );

        await _arweave.postTx(folderTx);

        await _driveDao.writeTransaction(folderEntity.toTransactionCompanion());
        await _driveDao.insertFolderRevision(
            folderEntity.toRevisionCompanion(RevisionAction.create));
      });
    } catch (err) {
      addError(err);
    }

    emit(FolderCreateSuccess());
  }

  Future<Map<String, dynamic>> _uniqueFolderName(
      AbstractControl<dynamic> control) async {
    final String folderName = control.value;

    // Check that the parent folder does not already have a folder with the input name.
    final foldersWithName = await _driveDao
        .foldersInFolderWithName(
            driveId: driveId, parentFolderId: parentFolderId, name: folderName)
        .get();
    final nameAlreadyExists = foldersWithName.isNotEmpty;

    if (nameAlreadyExists) {
      control.markAsTouched();
      return {AppValidationMessage.nameAlreadyPresent: true};
    }

    return null;
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(FolderCreateFailure());
    super.onError(error, stackTrace);
  }
}
