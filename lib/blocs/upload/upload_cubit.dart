import 'dart:async';

import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc/bloc.dart';
import 'package:file_picker_cross/file_picker_cross.dart';
import 'package:meta/meta.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';

import '../blocs.dart';

part 'upload_state.dart';

class UploadCubit extends Cubit<UploadState> {
  final String driveId;
  final String folderId;
  final FilePickerCross file;

  Map<String, FileEntity> uploadPathFiles;
  List<Transaction> uploadTransactions;

  final _uuid = Uuid();
  final ProfileBloc _profileBloc;
  final DriveDao _driveDao;
  final ArweaveService _arweave;

  UploadCubit({
    @required this.driveId,
    @required this.folderId,
    @required this.file,
    @required ProfileBloc profileBloc,
    @required DriveDao driveDao,
    @required ArweaveService arweave,
  })  : _profileBloc = profileBloc,
        _driveDao = driveDao,
        _arweave = arweave,
        super(UploadIdle()) {
    Future.microtask(() => prepareFileUpload());
  }

  Future<void> prepareFileUpload() async {
    emit(UploadPreparationInProgress());

    final profile = _profileBloc.state as ProfileLoaded;
    final targetDrive = await _driveDao.getDriveById(driveId);
    final targetFolder = await _driveDao.getFolderById(driveId, folderId);

    final fileName = basename(file.path);
    final filePath = '${targetFolder.path}/${fileName}';
    final fileEntity = FileEntity(
      driveId: targetDrive.id,
      name: fileName,
      size: file.length,
      // TODO: Replace with time reported by OS.
      lastModifiedDate: DateTime.now(),
      parentFolderId: targetFolder.id,
      dataContentType: lookupMimeType(fileName),
    );

    var existingFileId = await _driveDao.fileExistsInFolder(
      fileEntity.parentFolderId,
      fileEntity.name,
    );

    fileEntity.id = existingFileId ?? _uuid.v4();

    final driveKey = targetDrive.isPrivate
        ? await _driveDao.getDriveKey(targetDrive.id, profile.cipherKey)
        : null;

    final uploadTxs = await _arweave.prepareFileUploadTxs(
      fileEntity,
      file.toUint8List(),
      profile.wallet,
      driveKey,
    );

    uploadPathFiles = {filePath: fileEntity};
    uploadTransactions = [
      uploadTxs.entityTx,
      uploadTxs.dataTx,
    ];

    emit(
      UploadFileReady(
        fileName: fileEntity.name,
        uploadCost: uploadTxs.dataTx.reward,
        uploadSize: fileEntity.size,
      ),
    );
  }

  Future<void> startFileUpload() async {
    emit(UploadInProgress());

    await _arweave.batchPostTxs(uploadTransactions);

    for (final fileEntry in uploadPathFiles.entries) {
      await _driveDao.writeFileEntity(
        fileEntry.value,
        fileEntry.key,
      );
    }

    emit(UploadComplete());

    emit(UploadIdle());
  }
}
