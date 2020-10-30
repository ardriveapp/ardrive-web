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
      dataContentType: lookupMimeType(fileName),
    );

    fileEntity.id = previousState is UploadFileAlreadyExists
        ? previousState.existingFileId
        : _uuid.v4();

    final driveKey = _targetDrive.isPrivate
        ? await _driveDao.getDriveKey(_targetDrive.id, profile.cipherKey)
        : null;

    final uploadTxs = await _arweave.prepareFileUploadTxs(
      fileEntity,
      file.toUint8List(),
      profile.wallet,
      driveKey,
    );

    _fileUploadHandles = [
      _FileUploadHandle(
        entity: fileEntity,
        path: filePath,
        entityTx: uploadTxs.entityTx,
        dataTx: uploadTxs.dataTx,
      ),
    ];

    if (_fileUploadHandles.length == 1) {
      emit(
        UploadFileReady(
          fileName: fileEntity.name,
          uploadCost: uploadTxs.dataTx.reward,
          uploadSize: fileEntity.size,
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
