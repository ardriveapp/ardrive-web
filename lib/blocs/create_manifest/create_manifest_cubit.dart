import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/manifest_entity.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:bloc/bloc.dart';
import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:reactive_forms/reactive_forms.dart';

part 'create_manifest_state.dart';

class CreateManifestCubit extends Cubit<CreateManifestState> {
  late FormGroup form;

  // final FolderEntry ghostFolder;
  final ProfileCubit _profileCubit;
  final DriveID driveId;

  final ArweaveService _arweave;
  final DriveDao _driveDao;
  final SyncCubit _syncCubit;

  StreamSubscription? _selectedFolderSubscription;

  CreateManifestCubit({
    // required this.ghostFolder,
    required this.driveId,
    required ProfileCubit profileCubit,
    required ArweaveService arweave,
    required DriveDao driveDao,
    required SyncCubit syncCubit,
  })  : _profileCubit = profileCubit,
        _arweave = arweave,
        _driveDao = driveDao,
        _syncCubit = syncCubit,
        super(CreateManifestInitial()) {
    form = FormGroup({
      'name': FormControl(
        validators: [
          Validators.required,
          Validators.pattern(kFileNameRegex),
          Validators.pattern(kTrimTrailingRegex),
        ],
      ),
    });
  }
  Future<void> loadParentFolder() async {
    final state = this.state as CreateManifestFolderLoadSuccess;
    if (state.viewingFolder.folder.parentFolderId != null) {
      return loadFolder(state.viewingFolder.folder.parentFolderId!);
    }
  }

  Future<void> chooseFolder() async {
    if (form.invalid) {
      // Chosen manifest name must be valid before proceeding
      return;
    }

    await _driveDao
        .driveById(driveId: driveId)
        .getSingle()
        .then((d) => loadFolder(d.rootFolderId));
  }

  Future<void> loadFolder(String folderId) async {
    await _selectedFolderSubscription?.cancel();

    _selectedFolderSubscription =
        _driveDao.watchFolderContents(driveId, folderId: folderId).listen(
              (f) => emit(
                CreateManifestFolderLoadSuccess(
                  viewingRootFolder: f.folder.parentFolderId == null,
                  viewingFolder: f,
                  movingEntryId: f.folder.id,
                ),
              ),
            );
  }

  Future<void> checkForConflicts() async {
    final name = form.control('name').value;
    final parentFolderId =
        (state as CreateManifestFolderLoadSuccess).viewingFolder.folder.id;

    final foldersWithName = await _driveDao
        .foldersInFolderWithName(
            driveId: driveId, parentFolderId: parentFolderId, name: name)
        .get();
    final filesWithName = await _driveDao
        .filesInFolderWithName(
            driveId: driveId, parentFolderId: parentFolderId, name: name)
        .get();

    final conflictingFiles =
        filesWithName.where((e) => e.dataContentType != ContentType.manifest);

    if (foldersWithName.isNotEmpty || conflictingFiles.isNotEmpty) {
      // Name conflicts with existing file or folder
      // Send user back to naming the manifest
      emit(CreateManifestNameConflict(name: name));
    }

    final manifestRevisionId = filesWithName
        .firstWhereOrNull((e) => e.dataContentType == ContentType.manifest)
        ?.id;

    if (manifestRevisionId != null) {
      emit(CreateManifestRevisionConfirm(id: manifestRevisionId));
    }

    await uploadManifest();
  }

  Future<void> uploadManifest({FileID? existingManifestFileId}) async {
    try {
      final profile = _profileCubit.state as ProfileLoggedIn;
      final state = this.state as CreateManifestFolderLoadSuccess;

      final String folderName = form.control('name').value;
      final parentFolder = state.viewingFolder.folder;

      if (await _profileCubit.logoutIfWalletMismatch()) {
        emit(CreateManifestWalletMismatch());
        return;
      }

      final folderNode =
          (await _driveDao.getFolderTree(driveId, parentFolder.id));
      final arweaveManifest =
          ManifestEntity.fromFolderNode(folderNode: folderNode);

      print(arweaveManifest.toJson());

      // TODO: Upload this manifest as a data transaction
      // TODO: Upload a meta data transaction for this manifest file entity

      emit(CreateManifestUploadInProgress());
      emit(CreateManifestSuccess());
    } catch (err) {
      addError(err);
    }
  }

  @override
  Future<void> close() async {
    await _selectedFolderSubscription?.cancel();
    await super.close();
  }

  void backToName() {
    emit(CreateManifestInitial());
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(CreateManifestFailure());
    super.onError(error, stackTrace);

    print('Failed to create manifest: $error $stackTrace');
  }
}
