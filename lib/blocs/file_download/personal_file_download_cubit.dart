part of 'file_download_cubit.dart';

/// [ProfileFileDownloadCubit] includes logic to allow a user to download files
/// that they have attached to their profile.
class FileDownloadProgress extends LinearProgress {
  @override
  final double progress;

  FileDownloadProgress(this.progress);
}

class ProfileFileDownloadCubit extends FileDownloadCubit {
  final DriveID driveId;

  final FileID fileId;
  final StreamController<LinearProgress> _downloadProgress =
      StreamController<LinearProgress>.broadcast();
  Stream<LinearProgress> get downloadProgress => _downloadProgress.stream;
  final String fileName;
  final int fileSize;
  final String? dataContentType;
  final DateTime lastModified;

  final TxID revisionDataTxId;

  final ProfileCubit _profileCubit;
  final DriveDao _driveDao;
  final ArweaveService _arweave;
  final downloader = ArDriveDownloader();

  ProfileFileDownloadCubit({
    required this.driveId,
    required this.fileId,
    required this.fileName,
    required this.fileSize,
    required this.dataContentType,
    required this.lastModified,
    required this.revisionDataTxId,
    required ProfileCubit profileCubit,
    required DriveDao driveDao,
    required ArweaveService arweave,
  })  : _profileCubit = profileCubit,
        _driveDao = driveDao,
        _arweave = arweave,
        super(FileDownloadStarting()) {
    download();
  }

  Future<void> download() async {
    try {
      final drive = await _driveDao.driveById(driveId: driveId).getSingle();

      switch (drive.privacy) {
        case DrivePrivacy.private:
          await _downloadFile(fileName, fileSize, drive);
          break;
        case DrivePrivacy.public:
          if (Platform.isAndroid || Platform.isIOS) {
            final stream = downloader.downloadFile(
              '${_arweave.client.api.gatewayUrl.origin}/$revisionDataTxId',
              fileName,
            );

            await for (int progress in stream) {
              emit(
                FileDownloadWithProgress(
                  fileName: fileName,
                  progress: progress,
                  fileSize: fileSize,
                ),
              );
              _downloadProgress.sink.add(FileDownloadProgress(progress / 100));
            }

            emit(FileDownloadFinishedWithSuccess(fileName: fileName));
            break;
          }
          await _downloadFile(fileName, fileSize, drive);
          return;

        default:
      }
    } catch (err) {
      addError(err);
    }
  }

  Future<void> _downloadFile(String fileName, int fileSize, Drive drive) async {
    late Uint8List dataBytes;

    emit(
      FileDownloadInProgress(
        fileName: fileName,
        totalByteCount: fileSize,
      ),
    );
    final dataRes = await http.get(
      Uri.parse(
        '${_arweave.client.api.gatewayUrl.origin}/$revisionDataTxId',
      ),
    );
    final profile = _profileCubit.state;
    SecretKey? driveKey;

    if (profile is ProfileLoggedIn) {
      driveKey = await _driveDao.getDriveKey(
        drive.id,
        profile.cipherKey,
      );
    } else {
      driveKey = await _driveDao.getDriveKeyFromMemory(driveId);
    }

    if (driveKey == null) {
      throw StateError('Drive Key not found');
    }

    final fileKey = await _driveDao.getFileKey(fileId, driveKey);
    final dataTx = await (_arweave.getTransactionDetails(revisionDataTxId));

    if (dataTx != null) {
      dataBytes = await decryptTransactionData(
        dataTx,
        dataRes.bodyBytes,
        fileKey,
      );
    }
    emit(
      FileDownloadSuccess(
        bytes: dataBytes,
        fileName: fileName,
        mimeType: dataContentType ?? lookupMimeType(fileName),
        lastModified: lastModified,
      ),
    );
  }

  @override
  Future<void> abortDownload() async {
    emit(FileDownloadAborted());
    await downloader.cancelDownload();
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(FileDownloadFailure());
    super.onError(error, stackTrace);

    print('Failed to download personal file: $error $stackTrace');
  }
}
