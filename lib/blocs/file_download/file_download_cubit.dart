import 'dart:typed_data';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:http/http.dart' as http;
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
        super(FileDownloadStarting()) {
    download();
  }

  Future<void> download() async {
    try {
      final drive = await _driveDao.getDriveById(driveId);
      final file = await _driveDao.getFileById(driveId, fileId);

      emit(FileDownloadInProgress(
          fileName: file.name, totalByteCount: file.size));

      final dataRes = await http
          .get(_arweave.client.api.gatewayUrl.origin + '/${file.dataTxId}');

      Uint8List dataBytes;

      if (drive.isPublic) {
        dataBytes = dataRes.bodyBytes;
      } else if (drive.isPrivate) {
        final profile = _profileCubit.state as ProfileLoaded;

        final dataTx = await _arweave.getTransactionDetails(file.dataTxId);

        final driveKey =
            await _driveDao.getDriveKey(drive.id, profile.cipherKey);
        final fileKey = await deriveFileKey(driveKey, file.id);

        dataBytes =
            await decryptTransactionData(dataTx, dataRes.bodyBytes, fileKey);
      }

      emit(
        FileDownloadSuccess(
          fileName: file.name,
          fileExtension: extension(file.name),
          fileDataBytes: dataBytes,
        ),
      );
    } catch (err) {
      addError(err);
    }
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(FileDownloadFailure());
    super.onError(error, stackTrace);
  }
}
