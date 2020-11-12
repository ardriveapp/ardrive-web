import 'dart:async';
import 'dart:math' as math;

import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:file_picker_cross/file_picker_cross.dart';
import 'package:meta/meta.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart';
import 'package:pedantic/pedantic.dart';
import 'package:uuid/uuid.dart';

import '../blocs.dart';
import 'file_upload_handle.dart';

part 'upload_state.dart';

class UploadCubit extends Cubit<UploadState> {
  final String driveId;
  final String folderId;
  final List<FilePickerCross> files;

  final _uuid = Uuid();
  final ProfileCubit _profileCubit;
  final DriveDao _driveDao;
  final ArweaveService _arweave;

  Drive _targetDrive;
  FolderEntry _targetFolder;

  /// Map of conflicting file ids keyed by their file names.
  final Map<String, String> conflictingFiles = {};

  /// A map of [FileUploadHandle]s keyed by their respective file's id.
  final Map<String, FileUploadHandle> _fileUploadHandles = {};

  UploadCubit({
    @required this.driveId,
    @required this.folderId,
    @required this.files,
    @required ProfileCubit profileCubit,
    @required DriveDao driveDao,
    @required ArweaveService arweave,
  })  : _profileCubit = profileCubit,
        _driveDao = driveDao,
        _arweave = arweave,
        super(UploadPreparationInProgress()) {
    () async {
      _targetDrive = await _driveDao.getDriveById(driveId);
      _targetFolder = await _driveDao.getFolderById(driveId, folderId);

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
      final fileName = basename(file.path);
      final existingFileId = await _driveDao
          .selectFileInFolderByName(
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
    final profile = _profileCubit.state as ProfileLoaded;

    emit(UploadPreparationInProgress());

    for (final file in files) {
      final uploadHandle = await prepareFileUpload(file);
      _fileUploadHandles[uploadHandle.entity.id] = uploadHandle;
    }

    final uploadCost = _fileUploadHandles.values
        .map((f) => f.cost)
        .reduce((total, cost) => total + cost);

    emit(
      UploadReady(
        files: _fileUploadHandles.values.toList(),
        uploadCost: uploadCost,
        insufficientArBalance: profile.walletBalance < uploadCost,
      ),
    );
  }

  Future<void> startUpload() async {
    emit(UploadInProgress(files: _fileUploadHandles.values.toList()));

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

  Future<FileUploadHandle> prepareFileUpload(FilePickerCross file) async {
    final profile = _profileCubit.state as ProfileLoaded;

    final fileName = basename(file.path);
    final filePath = '${_targetFolder.path}/${fileName}';
    final fileEntity = FileEntity(
      driveId: _targetDrive.id,
      name: fileName,
      size: file.length,
      // TODO: Replace with time reported by OS.
      lastModifiedDate: DateTime.now(),
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

    final fileData = file.toUint8List();

    final uploadHandle = FileUploadHandle(entity: fileEntity, path: filePath);

    // Only use [DataBundle]s if the file being uploaded can be serialised as one.
    // The limitation occurs as a result of string size limitations in JS implementations which is about 512MB.
    // We aim switch slightly below that to give ourselves some buffer.
    final fileSizeWithinBundleLimits =
        fileData.lengthInBytes < (512 - 12) * math.pow(10, 6);

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
