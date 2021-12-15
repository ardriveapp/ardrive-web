import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/l11n/validation_messages.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:reactive_forms/reactive_forms.dart';

part 'ghost_fixer_state.dart';

class GhostFixerCubit extends Cubit<GhostFixerState> {
  late FormGroup form;

  final FolderEntry ghostFolder;
  final ProfileCubit _profileCubit;

  final ArweaveService _arweave;
  final DriveDao _driveDao;

  GhostFixerCubit({
    required this.ghostFolder,
    required ProfileCubit profileCubit,
    required ArweaveService arweave,
    required DriveDao driveDao,
  })  : _profileCubit = profileCubit,
        _arweave = arweave,
        _driveDao = driveDao,
        super(GhostFixerInitial()) {
    form = FormGroup({
      'name': FormControl(
        validators: [
          Validators.required,
          Validators.pattern(kFileNameRegex),
          Validators.pattern(kTrimTrailingRegex),
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

    try {
      final profile = _profileCubit.state as ProfileLoggedIn;
      final String folderName = form.control('name').value;
      if (await _profileCubit.logoutIfWalletMismatch()) {
        emit(GhostFixerWalletMismatch());
        return;
      }
      emit(GhostFixerInProgress());

      await _driveDao.transaction(() async {
        final targetDrive =
            await _driveDao.driveById(driveId: ghostFolder.driveId).getSingle();
        final targetFolder = await _driveDao
            .folderById(
              driveId: ghostFolder.driveId,
              folderId: ghostFolder.parentFolderId!,
            )
            .getSingle();

        final driveKey = targetDrive.isPrivate
            ? await _driveDao.getDriveKey(
                targetFolder.driveId, profile.cipherKey)
            : null;

        final newFolderId = await _driveDao.createFolderWithId(
          id: ghostFolder.id,
          driveId: targetFolder.driveId,
          parentFolderId: targetFolder.id,
          folderName: folderName,
          path: '${targetFolder.path}/$folderName',
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
        folderEntity.txId = folderTx.id;
        await _driveDao.insertFolderRevision(folderEntity.toRevisionCompanion(
            performedAction: RevisionAction.create));
      });
    } catch (err) {
      addError(err);
    }

    emit(GhostFixerSuccess());
  }

  Future<Map<String, dynamic>?> _uniqueFolderName(
      AbstractControl<dynamic> control) async {
    final String folderName = control.value;

    // Check that the parent folder does not already have a folder with the input name.
    final foldersWithName = await _driveDao
        .foldersInFolderWithName(
          driveId: ghostFolder.driveId,
          parentFolderId: ghostFolder.parentFolderId,
          name: folderName,
        )
        .get();
    final nameAlreadyExists = foldersWithName.isNotEmpty;

    if (nameAlreadyExists) {
      control.markAsTouched();
      return {AppValidationMessage.fsEntryNameAlreadyPresent: true};
    }

    return null;
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(GhostFixerFailure());
    super.onError(error, stackTrace);

    print('Failed to create folder: $error $stackTrace');
  }
}
