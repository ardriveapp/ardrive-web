import 'dart:async';

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

part 'upload_state.dart';

class UploadCubit extends Cubit<UploadState> {
  final String driveId;
  final String folderId;
  final FilePickerCross file;

  final _uuid = Uuid();
  final ProfileCubit _profileCubit;
  final DriveDao _driveDao;
  final ArweaveService _arweave;

  Drive _targetDrive;
  FolderEntry _targetFolder;
  List<_FileUploadHandle> _fileUploadHandles;

  UploadCubit({
    @required this.driveId,
    @required this.folderId,
    @required this.file,
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
      unawaited(checkTargetFileVersioning());
    }();
  }

  /// Tries to find a file in the target folder by the same name as the file being uploaded.
  ///
  /// If there's one, prompt the user to upload the file as a version of the existing one.
  /// If there isn't one, prepare to upload the file.
  Future<void> checkTargetFileVersioning() async {
    emit(UploadPreparationInProgress());

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
      emit(UploadFileAlreadyExists(
          existingFileId: existingFileId, existingFileName: fileName));
    } else {
      unawaited(prepareUpload());
    }
  }

  Future<void> prepareUpload() async {
    final previousState = state;

    emit(UploadPreparationInProgress());

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

    fileEntity.id = previousState is UploadFileAlreadyExists
        ? previousState.existingFileId
        : _uuid.v4();

    final private = _targetDrive.isPrivate;
    final driveKey = private
        ? await _driveDao.getDriveKey(_targetDrive.id, profile.cipherKey)
        : null;
    final fileKey =
        private ? await deriveFileKey(driveKey, fileEntity.id) : null;

    final fileData = file.toUint8List();
    final fileDataTx = await _arweave.client.transactions.prepare(
      private
          ? await createEncryptedTransaction(fileData, fileKey)
          : Transaction.withBlobData(data: fileData),
      profile.wallet,
    );

    fileDataTx.addApplicationTags();

    // Don't include the file's Content-Type tag if it is meant to be private.
    if (!private) {
      fileDataTx.addTag(
        EntityTag.contentType,
        fileEntity.dataContentType,
      );
    }

    await fileDataTx.sign(profile.wallet);

    fileEntity.dataTxId = fileDataTx.id;

    final fileEntityTx =
        await _arweave.prepareEntityTx(fileEntity, profile.wallet, fileKey);

    // Sometimes, files that are too large will result in the transaction having a data size of zero.
    // TODO: Investigate problems with large file uploads on web.
    if (fileDataTx.dataSize == '0' || fileDataTx.reward == BigInt.zero) {
      emit(UploadPreparationFailure());
      return;
    }

    _fileUploadHandles = [
      _FileUploadHandle(
        entity: fileEntity,
        path: filePath,
        entityTx: fileEntityTx,
        dataTx: fileDataTx,
      ),
    ];

    if (_fileUploadHandles.length == 1) {
      final uploadCost = fileDataTx.reward;

      emit(
        UploadFileReady(
          fileName: fileEntity.name,
          uploadCost: uploadCost,
          uploadSize: fileEntity.size,
          insufficientArBalance: profile.walletBalance < uploadCost,
        ),
      );
    } else {}
  }

  Future<void> startUpload() async {
    if (_fileUploadHandles.length == 1) {
      final uploadHandle = _fileUploadHandles.single;
      final uploadEntity = uploadHandle.entity;

      emit(UploadFileInProgress(
          fileName: uploadHandle.entity.name, fileSize: uploadEntity.size));

      await _arweave.postTx(uploadHandle.entityTx);

      await for (final upload
          in _arweave.client.transactions.upload(uploadHandle.dataTx)) {
        final uploadProgress = upload.percentageComplete / 100;

        emit(UploadFileInProgress(
          fileName: uploadHandle.entity.name,
          fileSize: uploadEntity.size,
          uploadProgress: uploadProgress,
          uploadedFileSize: (uploadEntity.size * uploadProgress).toInt(),
        ));
      }
    } else {
      for (final uploadHandle in _fileUploadHandles) {
        await _arweave
            .batchPostTxs([uploadHandle.entityTx, uploadHandle.dataTx]);
      }
    }

    for (final uploadHandle in _fileUploadHandles) {
      await _driveDao.writeFileEntity(uploadHandle.entity, uploadHandle.path);
    }

    emit(UploadComplete());
  }
}

class _FileUploadHandle {
  final FileEntity entity;
  final String path;

  final Transaction entityTx;
  final Transaction dataTx;

  _FileUploadHandle({this.entity, this.path, this.entityTx, this.dataTx});
}
