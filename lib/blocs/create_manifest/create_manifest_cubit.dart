import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/manifest_entity.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc/bloc.dart';
import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:uuid/uuid.dart';

part 'create_manifest_state.dart';

class CreateManifestCubit extends Cubit<CreateManifestState> {
  late FormGroup form;

  final ProfileCubit _profileCubit;
  final Drive drive;

  final ArweaveService _arweave;
  final DriveDao _driveDao;
  final PstService _pst;

  StreamSubscription? _selectedFolderSubscription;

  CreateManifestCubit({
    required this.drive,
    required ProfileCubit profileCubit,
    required ArweaveService arweave,
    required DriveDao driveDao,
    required PstService pst,
  })  : _profileCubit = profileCubit,
        _arweave = arweave,
        _driveDao = driveDao,
        _pst = pst,
        super(CreateManifestInitial()) {
    if (drive.isPrivate) {
      // Extra guardrail to prevent private drives from creating manifests
      // Private manifests need more consideration and are currently unavailable
      emit(CreateManifestPrivacyMismatch());
    }

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

    await loadFolder(drive.rootFolderId);
  }

  Future<void> loadFolder(String folderId) async {
    await _selectedFolderSubscription?.cancel();

    _selectedFolderSubscription =
        _driveDao.watchFolderContents(drive.id, folderId: folderId).listen(
              (f) => emit(
                CreateManifestFolderLoadSuccess(
                  viewingRootFolder: f.folder.parentFolderId == null,
                  viewingFolder: f,
                ),
              ),
            );
  }

  Future<void> checkForConflicts({required FolderEntry parentFolder}) async {
    await _selectedFolderSubscription?.cancel();

    final name = form.control('name').value;

    final foldersWithName = await _driveDao
        .foldersInFolderWithName(
            driveId: drive.id, parentFolderId: parentFolder.id, name: name)
        .get();
    final filesWithName = await _driveDao
        .filesInFolderWithName(
            driveId: drive.id, parentFolderId: parentFolder.id, name: name)
        .get();

    final conflictingFiles =
        filesWithName.where((e) => e.dataContentType != ContentType.manifest);

    if (foldersWithName.isNotEmpty || conflictingFiles.isNotEmpty) {
      // Name conflicts with existing file or folder
      // This is an error case, send user back to naming the manifest
      emit(CreateManifestNameConflict(name: name, parentFolder: parentFolder));
      return;
    }

    final manifestRevisionId = filesWithName
        .firstWhereOrNull((e) => e.dataContentType == ContentType.manifest)
        ?.id;

    if (manifestRevisionId != null) {
      emit(CreateManifestRevisionConfirm(
          id: manifestRevisionId, parentFolder: parentFolder));
      return;
    }

    await uploadManifest(parentFolder: parentFolder);
  }

  Future<void> uploadManifest(
      {FileID? existingManifestFileId,
      required FolderEntry parentFolder}) async {
    if (await _profileCubit.logoutIfWalletMismatch()) {
      emit(CreateManifestWalletMismatch());
      return;
    }

    emit(CreateManifestUploadInProgress());

    try {
      final folderNode =
          (await _driveDao.getFolderTree(drive.id, parentFolder.id));
      final arweaveManifest =
          ManifestEntity.fromFolderNode(folderNode: folderNode);

      final wallet = (_profileCubit.state as ProfileLoggedIn).wallet;
      final String manifestName = form.control('name').value;

      final manifestDataItem =
          await arweaveManifest.asPreparedDataItem(wallet: wallet);
      await manifestDataItem.sign(wallet);

      /// Assemble data JSON of the metadata tx for the manifest
      final manifestFileEntity = FileEntity(
          size: arweaveManifest.size,
          parentFolderId: parentFolder.id,
          name: manifestName,
          lastModifiedDate: DateTime.now(),
          id: existingManifestFileId ?? Uuid().v4(),
          driveId: drive.id,
          dataTxId: manifestDataItem.id,
          dataContentType: ContentType.manifest);

      final manifestMetaDataItem =
          await _arweave.prepareEntityDataItem(manifestFileEntity, wallet);

      // Sign data item and preserve meta data tx ID on entity
      await manifestMetaDataItem.sign(wallet);
      manifestFileEntity.txId = manifestMetaDataItem.id;

      final bundle = await DataBundle.fromDataItems(
          items: [manifestDataItem, manifestMetaDataItem]);

      final bundleTx = await _arweave.prepareDataBundleTxFromBlob(
        bundle.blob,
        wallet,
      );

      // Add tips to bundle tx
      final bundleTip = await _pst.getPSTFee(bundleTx.reward);
      bundleTx
        ..addTag(TipType.tagName, TipType.dataUpload)
        ..setTarget(await _pst.getWeightedPstHolder())
        ..setQuantity(bundleTip);

      // Sign bundle tx and preserve bundle tx ID on entity
      await bundleTx.sign(wallet);
      manifestFileEntity.bundledIn = bundleTx.id;

      // Write manifest file entity to the data base
      await _driveDao.transaction(() async {
        await _driveDao.writeFileEntity(
            manifestFileEntity, '${parentFolder.path}/$manifestName');
        await _driveDao.insertFileRevision(
          manifestFileEntity.toRevisionCompanion(
              performedAction: existingManifestFileId == null
                  ? RevisionAction.create
                  : RevisionAction.uploadNewVersion),
        );
      });

      // Upload the bundle
      await _arweave.client.transactions.upload(bundleTx).drain();
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
