import 'dart:typed_data';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart';

part 'file_download_state.dart';

class FileDownloadCubit extends Cubit<FileDownloadState> {
  final String driveId;
  final String fileId;

  final ProfileCubit _profileCubit;
  final DriveDao _driveDao;
  final ArweaveService _arweave;

  FileDownloadCubit({
    @required this.driveId,
    @required this.fileId,
    @required ProfileCubit profileCubit,
    @required DriveDao driveDao,
    @required ArweaveService arweave,
  })  : _profileCubit = profileCubit,
        _driveDao = driveDao,
        _arweave = arweave,
        super(FileDownloadInProgress()) {
    download();
  }

  Future<void> download() async {
    emit(FileDownloadInProgress());

    final drive = await _driveDao.getDriveById(driveId);
    final file = await _driveDao.getFileById(driveId, fileId);

    final dataTx = await _arweave.getTransactionDetails(file.dataTxId);

    final dataRaw = await _arweave.client.transactions.getData(file.dataTxId);
    Uint8List dataBytes;

    if (drive.isPublic) {
      dataBytes = utils.decodeBase64ToBytes(dataRaw);
    } else if (drive.isPrivate) {
      final profile = _profileCubit.state as ProfileLoaded;
      final driveKey = await _driveDao.getDriveKey(drive.id, profile.cipherKey);
      final fileKey = await deriveFileKey(driveKey, file.id);

      dataBytes = await decryptTransactionData(
          dataTx, utils.decodeBase64ToBytes(dataRaw), fileKey);
    }

    emit(
      FileDownloadSuccess(
        fileName: file.name,
        fileExtension: extension(file.name),
        fileDataBytes: dataBytes,
      ),
    );
  }
}
