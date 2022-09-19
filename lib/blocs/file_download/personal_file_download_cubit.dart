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
  final TxID dataTxId;
  final StreamController<LinearProgress> _downloadProgress =
      StreamController<LinearProgress>.broadcast();
  Stream<LinearProgress> get downloadProgress => _downloadProgress.stream;

  final ProfileCubit _profileCubit;
  final DriveDao _driveDao;
  final ArweaveService _arweave;
  final downloader = ArDriveDownloader();

  ProfileFileDownloadCubit({
    required this.driveId,
    required this.fileId,
    required this.dataTxId,
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
      final file = await _driveDao
          .fileById(driveId: driveId, fileId: fileId)
          .getSingle();

      switch (drive.privacy) {
        case DrivePrivacy.private:
          await _downloadFile(file, drive);
          break;
        case DrivePrivacy.public:
          if (kIsWeb) {
            await _downloadFile(file, drive);
            return;
          }

          final stream = downloader.downloadFile(
            '${_arweave.client.api.gatewayUrl.origin}/$dataTxId',
            file.name,
          );

          await for (int progress in stream) {
            emit(
              FileDownloadWithProgress(
                fileName: file.name,
                progress: progress,
                fileSize: file.size,
              ),
            );
            _downloadProgress.sink.add(FileDownloadProgress(progress / 100));
          }

          emit(FileDownloadFinishedWithSuccess(fileName: file.name));
          break;

        default:
      }
    } catch (err) {
      addError(err);
    }
  }

  Future<void> _downloadFile(FileEntry file, Drive drive) async {
    late Uint8List dataBytes;

    emit(
      FileDownloadInProgress(
        fileName: file.name,
        totalByteCount: file.size,
      ),
    );
    final dataRes = await http.get(
      Uri.parse(
        '${_arweave.client.api.gatewayUrl.origin}/$dataTxId',
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
    final dataTx = await (_arweave.getTransactionDetails(file.dataTxId));

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
        fileName: file.name,
        mimeType: file.dataContentType ?? lookupMimeType(file.name),
        lastModified: file.lastModifiedDate,
      ),
    );
  }

  @override
  void abortDownload() {
    emit(FileDownloadAborted());
    downloader.cancelDownload();
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(FileDownloadFailure());
    super.onError(error, stackTrace);

    print('Failed to download personal file: $error $stackTrace');
  }
}
