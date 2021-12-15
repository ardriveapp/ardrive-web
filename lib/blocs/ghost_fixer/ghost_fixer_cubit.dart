import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
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
  final SyncCubit _syncCubit;

  StreamSubscription? _folderSubscription;

  GhostFixerCubit({
    required this.ghostFolder,
    required ProfileCubit profileCubit,
    required ArweaveService arweave,
    required DriveDao driveDao,
    required SyncCubit syncCubit,
  })  : _profileCubit = profileCubit,
        _arweave = arweave,
        _driveDao = driveDao,
        _syncCubit = syncCubit,
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
    _driveDao
        .driveById(driveId: ghostFolder.driveId)
        .getSingle()
        .then((d) => loadFolder(d.rootFolderId));
  }
  Future<void> loadParentFolder() async {
    final state = this.state as GhostFixerFolderLoadSuccess;
    if (state.viewingFolder.folder?.parentFolderId != null) {
      return loadFolder(state.viewingFolder.folder!.parentFolderId!);
    }
  }

  Future<void> loadFolder(String folderId) async {
    unawaited(_folderSubscription?.cancel());

    _folderSubscription = _driveDao
        .watchFolderContents(ghostFolder.driveId, folderId: folderId)
        .listen(
          (f) => emit(
            GhostFixerFolderLoadSuccess(
              viewingRootFolder: f.folder?.parentFolderId == null,
              viewingFolder: f,
              movingEntryId: ghostFolder.id,
            ),
          ),
        );
  }

  Future<bool> entityNameExists({
    required String name,
    required String parentFolderId,
  }) async {
    final foldersWithName = await _driveDao
        .foldersInFolderWithName(
            driveId: ghostFolder.driveId,
            parentFolderId: parentFolderId,
            name: name)
        .get();
    final filesWithName = await _driveDao
        .filesInFolderWithName(
            driveId: ghostFolder.driveId,
            parentFolderId: parentFolderId,
            name: name)
        .get();
    return foldersWithName.isNotEmpty || filesWithName.isNotEmpty;
  }

  Future<void> submit() async {
    form.markAllAsTouched();

    if (form.invalid) {
      return;
    }

    try {
      final profile = _profileCubit.state as ProfileLoggedIn;
      final state = this.state as GhostFixerFolderLoadSuccess;

      final String folderName = form.control('name').value;
      final parentFolder = state.viewingFolder.folder!;

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

        final folder = ghostFolder.copyWith(
          id: ghostFolder.id,
          name: folderName,
          parentFolderId: parentFolder.id,
          path: '${parentFolder.path}/$folderName',
          isGhost: false,
        );

        final folderEntity = folder.asEntity();

        final folderTx = await _arweave.prepareEntityTx(
          folderEntity,
          profile.wallet,
          driveKey,
        );

        await _arweave.postTx(folderTx);
        await _driveDao.writeToFolder(folder);

        folderEntity.txId = folderTx.id;
        await _driveDao.insertFolderRevision(folderEntity.toRevisionCompanion(
            performedAction: RevisionAction.create));
        final folderMap = {folder.id: folder.toCompanion(false)};
        await _syncCubit.generateFsEntryPaths(folder.driveId, folderMap, {});
      });
    } catch (err) {
      addError(err);
    }

    emit(GhostFixerSuccess());
  }

  Future<Map<String, dynamic>?> _uniqueFolderName(
      AbstractControl<dynamic> control) async {
    final state = this.state as GhostFixerFolderLoadSuccess;

    final String folderName = control.value;
    final parentFolder = state.viewingFolder.folder;

    // Check that the parent folder does not already have a folder with the input name.
    final nameAlreadyExists = await entityNameExists(
        name: folderName, parentFolderId: parentFolder!.id);

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
