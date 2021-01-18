import 'dart:async';

import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:file_selector/file_selector.dart';
import 'package:meta/meta.dart';
import 'package:mime/mime.dart';
import 'package:pedantic/pedantic.dart';
import 'package:uuid/uuid.dart';

import '../blocs.dart';
import 'file_upload_handle.dart';

part 'upload_state.dart';

class UploadCubit extends Cubit<UploadState> {
  final String driveId;
  final String folderId;
  final List<XFile> files;

  final _uuid = Uuid();
  final ProfileCubit _profileCubit;
  final DriveDao _driveDao;
  final ArweaveService _arweave;
  final PstService _pst;

  Drive _targetDrive;
  FolderEntry _targetFolder;

  /// Map of conflicting file ids keyed by their file names.
  final Map<String, String> conflictingFiles = {};

  /// A map of [FileUploadHandle]s keyed by their respective file's id.
  final Map<String, FileUploadHandle> _fileUploadHandles = {};

  /// The [Transaction] that pays `pstFee` to a random PST holder.
  Transaction feeTx;

  UploadCubit({
    @required this.driveId,
    @required this.folderId,
    @required this.files,
    @required ProfileCubit profileCubit,
    @required DriveDao driveDao,
    @required ArweaveService arweave,
    @required PstService pst,
  })  : _profileCubit = profileCubit,
        _driveDao = driveDao,
        _arweave = arweave,
        _pst = pst,
        super(UploadPreparationInProgress()) {
    () async {
      _targetDrive = await _driveDao.driveById(driveId).getSingle();
      _targetFolder = await _driveDao.folderById(driveId, folderId).getSingle();

      unawaited(checkConflictingFiles());
    }();
  }

  /// Tries to find a files that conflict with the files in the target folder.
  ///
  /// If there's one, prompt the user to upload the file as a version of the existing one.
  /// If there isn't one, prepare to upload the file.
  Future<void> checkConflictingFiles() async {
    emit(UploadPreparationInProgress());

    for (final file in files) {
      final fileName = file.name;
      final existingFileId = await _driveDao
          .filesInFolderWithName(
            _targetDrive.id,
            _targetFolder.id,
            fileName,
          )
          .map((f) => f.id)
          .getSingle();

      if (existingFileId != null) {
        conflictingFiles[fileName] = existingFileId;
      }
    }

    if (conflictingFiles.isNotEmpty) {
      emit(UploadFileConflict(
          conflictingFileNames: conflictingFiles.keys.toList()));
    } else {
      unawaited(prepareUpload());
    }
  }

  Future<void> prepareUpload() async {
    final profile = _profileCubit.state as ProfileLoggedIn;

    emit(UploadPreparationInProgress());

    for (final file in files) {
      final uploadHandle = await prepareFileUpload(file);
      _fileUploadHandles[uploadHandle.entity.id] = uploadHandle;
    }

    final uploadCost = _fileUploadHandles.values
        .map((f) => f.cost)
        .reduce((total, cost) => total + cost);

    var pstFee = BigInt.zero;

    try {
      // Workaround [BigInt] percentage division problems
      // by first multiplying by the percentage * 100 and then dividing by 100.
      pstFee = uploadCost *
          BigInt.from((await _pst.getPstFeePercentage()) * 100) ~/
          BigInt.from(100);

      feeTx = await _arweave.client.transactions.prepare(
        Transaction(
          target: await _pst.getWeightedPstHolder(),
          quantity: pstFee,
        ),
        profile.wallet,
      )
        ..addApplicationTags()
        ..addTag('Type', 'fee')
        ..addTag(TipType.tagName, TipType.dataUpload);

      await feeTx.sign(profile.wallet);
    } on UnimplementedError catch (_) {}

    final totalCost = uploadCost + pstFee;

    emit(
      UploadReady(
        uploadCost: uploadCost,
        pstFee: pstFee,
        totalCost: totalCost,
        uploadIsPublic: _targetDrive.isPublic,
        sufficientArBalance: profile.walletBalance >= totalCost,
        files: _fileUploadHandles.values.toList(),
      ),
    );
  }

  Future<void> startUpload() async {
    emit(UploadInProgress(files: _fileUploadHandles.values.toList()));

    if (feeTx != null) {
      await _arweave.postTx(feeTx);
    }

    await _driveDao.transaction(() async {
      for (final uploadHandle in _fileUploadHandles.values) {
        await _driveDao.writeFileEntity(uploadHandle.entity, uploadHandle.path);

        await for (final _ in uploadHandle.upload(_arweave)) {
          emit(UploadInProgress(files: _fileUploadHandles.values.toList()));
        }
      }
    });

    emit(UploadComplete());
  }

  Future<FileUploadHandle> prepareFileUpload(XFile file) async {
    final profile = _profileCubit.state as ProfileLoggedIn;

    final fileName = file.name;
    final filePath = '${_targetFolder.path}/${fileName}';
    final fileEntity = FileEntity(
      driveId: _targetDrive.id,
      name: fileName,
      size: await file.length(),
      lastModifiedDate: await file.lastModified(),
      parentFolderId: _targetFolder.id,
      dataContentType: lookupMimeType(fileName) ?? 'application/octet-stream',
    );

    // If this file conflicts with one that already exists in the target folder reuse the id of the conflicting file.
    fileEntity.id = conflictingFiles[fileName] ?? _uuid.v4();

    final private = _targetDrive.isPrivate;
    final driveKey = private
        ? await _driveDao.getDriveKey(_targetDrive.id, profile.cipherKey)
        : null;
    final fileKey =
        private ? await deriveFileKey(driveKey, fileEntity.id) : null;

    final fileData = await file.readAsBytes();

    final uploadHandle = FileUploadHandle(entity: fileEntity, path: filePath);

    // Only use [DataBundle]s if the file being uploaded can be serialised as one.
    // The limitation occurs as a result of string size limitations in JS implementations which is about 512MB.
    // We aim switch slightly below that to give ourselves some buffer.
    //
    // TODO: Reenable once we understand the problems with data bundle transactions.
    final fileSizeWithinBundleLimits = false;
    // fileData.lengthInBytes < (512 - 12) * math.pow(10, 6);

    if (fileSizeWithinBundleLimits) {
      uploadHandle.dataTx = private
          ? await createEncryptedDataItem(fileData, fileKey)
          : DataItem.withBlobData(data: fileData);
      uploadHandle.dataTx.setOwner(profile.wallet.owner);
    } else {
      uploadHandle.dataTx = await _arweave.client.transactions.prepare(
        private
            ? await createEncryptedTransaction(fileData, fileKey)
            : Transaction.withBlobData(data: fileData),
        profile.wallet,
      );
    }

    uploadHandle.dataTx.addApplicationTags();

    // Don't include the file's Content-Type tag if it is meant to be private.
    if (!private) {
      uploadHandle.dataTx.addTag(
        EntityTag.contentType,
        fileEntity.dataContentType,
      );
    }

    await uploadHandle.dataTx.sign(profile.wallet);

    fileEntity.dataTxId = uploadHandle.dataTx.id;

    if (fileSizeWithinBundleLimits) {
      uploadHandle.entityTx = await _arweave.prepareEntityDataItem(
          fileEntity, profile.wallet, fileKey);

      uploadHandle.bundleTx = await _arweave.prepareDataBundleTx(
        DataBundle(
          items: [
            uploadHandle.entityTx as DataItem,
            uploadHandle.dataTx as DataItem,
          ],
        ),
        profile.wallet,
      );
    } else {
      uploadHandle.entityTx =
          await _arweave.prepareEntityTx(fileEntity, profile.wallet, fileKey);
    }

    return uploadHandle;
  }
}
