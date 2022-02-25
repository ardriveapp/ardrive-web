import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/manifest_data.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';
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

  /// Validate form before User begins choosing a target folder
  Future<void> chooseTargetFolder() async {
    if (form.invalid) {
      return;
    }
    await loadFolder(drive.rootFolderId);
  }

  /// User has confirmed that they would like to submit a manifest revision transaction
  Future<void> confirmRevision() async {
    final revisionConfirmationState = state as CreateManifestRevisionConfirm;
    final parentFolder = revisionConfirmationState.parentFolder;
    final existingManifestFileId =
        revisionConfirmationState.existingManifestFileId;

    emit(CreateManifestPreparingManifest(parentFolder: parentFolder));
    await prepareManifestTx(existingManifestFileId: existingManifestFileId);
  }

  Future<void> loadParentFolder() async {
    final state = this.state as CreateManifestFolderLoadSuccess;
    if (state.viewingFolder.folder.parentFolderId != null) {
      return loadFolder(state.viewingFolder.folder.parentFolderId!);
    }
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

  /// User selected a new name due to name conflict, confirm that form is valid and check for conflicts again
  Future<void> reCheckConflicts() async {
    final conflictState = (state as CreateManifestNameConflict);
    final parentFolder = conflictState.parentFolder;
    final conflictingName = conflictState.conflictingName;

    if (form.invalid || form.control('name').value == conflictingName) {
      return;
    }

    emit(CreateManifestCheckingForConflicts(parentFolder: parentFolder));
    await checkNameConflicts();
  }

  Future<void> checkForConflicts() async {
    final parentFolder =
        (state as CreateManifestFolderLoadSuccess).viewingFolder.folder;

    emit(CreateManifestCheckingForConflicts(parentFolder: parentFolder));
    await checkNameConflicts();
  }

  Future<void> checkNameConflicts() async {
    final parentFolder =
        (state as CreateManifestCheckingForConflicts).parentFolder;
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
      emit(
        CreateManifestNameConflict(
          conflictingName: name,
          parentFolder: parentFolder,
        ),
      );
      return;
    }

    final manifestRevisionId = filesWithName
        .firstWhereOrNull((e) => e.dataContentType == ContentType.manifest)
        ?.id;

    if (manifestRevisionId != null) {
      emit(CreateManifestRevisionConfirm(
          existingManifestFileId: manifestRevisionId,
          parentFolder: parentFolder));
      return;
    }
    emit(CreateManifestPreparingManifest(parentFolder: parentFolder));
    await prepareManifestTx();
  }

  Future<void> prepareManifestTx({
    FileID? existingManifestFileId,
  }) async {
    try {
      final parentFolder =
          (state as CreateManifestPreparingManifest).parentFolder;
      final folderNode =
          (await _driveDao.getFolderTree(drive.id, parentFolder.id));
      final arweaveManifest =
          ManifestData.fromFolderNode(folderNode: folderNode);

      final profile = _profileCubit.state as ProfileLoggedIn;
      final wallet = profile.wallet;
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
        dataContentType: ContentType.manifest,
      );

      final manifestMetaDataItem = await _arweave.prepareEntityDataItem(
        manifestFileEntity,
        wallet,
      );

      // Sign data item and preserve meta data tx ID on entity
      await manifestMetaDataItem.sign(wallet);
      manifestFileEntity.txId = manifestMetaDataItem.id;

      final bundle = await DataBundle.fromDataItems(
        items: [manifestDataItem, manifestMetaDataItem],
      );

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

      final totalCost = bundleTx.reward + bundleTx.quantity;

      if (profile.walletBalance < totalCost) {
        emit(CreateManifestInsufficientBalance());
        return;
      }

      final arUploadCost = winstonToAr(totalCost);
      final usdUploadCost = await _arweave.getArUsdConversionRate().then(
          (conversionRate) => double.parse(arUploadCost) * conversionRate);

      // Sign bundle tx and preserve bundle tx ID on entity
      await bundleTx.sign(wallet);
      manifestFileEntity.bundledIn = bundleTx.id;

      final uploadManifestParams = UploadManifestParams(
        signedBundleTx: bundleTx,
        addManifestToDatabase: _driveDao.transaction(() async {
          await _driveDao.writeFileEntity(
              manifestFileEntity, '${parentFolder.path}/$manifestName');
          await _driveDao.insertFileRevision(
            manifestFileEntity.toRevisionCompanion(
                performedAction: existingManifestFileId == null
                    ? RevisionAction.create
                    : RevisionAction.uploadNewVersion),
          );
        }),
      );

      emit(
        CreateManifestUploadConfirmation(
          manifestSize: arweaveManifest.size,
          manifestName: manifestName,
          arUploadCost: arUploadCost,
          usdUploadCost: usdUploadCost,
          uploadManifestParams: uploadManifestParams,
        ),
      );
    } catch (err) {
      addError(err);
    }
  }

  Future<void> uploadManifest() async {
    if (await _profileCubit.logoutIfWalletMismatch()) {
      emit(CreateManifestWalletMismatch());
      return;
    }

    final params =
        (state as CreateManifestUploadConfirmation).uploadManifestParams;

    emit(CreateManifestUploadInProgress());
    try {
      await _arweave.client.transactions.upload(params.signedBundleTx).drain();
      await params.addManifestToDatabase;

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
    form.reset();
    emit(CreateManifestInitial());
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(CreateManifestFailure());
    super.onError(error, stackTrace);

    print('Failed to create manifest: $error $stackTrace');
  }
}

class UploadManifestParams {
  final Transaction signedBundleTx;
  final Future<void> addManifestToDatabase;

  UploadManifestParams(
      {required this.signedBundleTx, required this.addManifestToDatabase});
}
