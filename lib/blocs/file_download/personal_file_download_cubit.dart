part of 'file_download_cubit.dart';

/// [ProfileFileDownloadCubit] includes logic to allow a user to download files
/// that they have attached to their profile.
class FileDownloadProgress extends LinearProgress {
  @override
  final double progress;

  FileDownloadProgress(this.progress);
}

class ProfileFileDownloadCubit extends FileDownloadCubit {
  final ARFSFileEntity _file;

  final StreamController<LinearProgress> _downloadProgress =
      StreamController<LinearProgress>.broadcast();

  Stream<LinearProgress> get downloadProgress => _downloadProgress.stream;

  final _privateFileLimit = const MiB(300).size;
  final _warningDownloadTimeLimit = const MiB(200).size;

  final DriveDao _driveDao;
  final ArweaveService _arweave;
  final ArDriveDownloader _downloader;
  final DownloadService _downloadService;
  final Decrypt _decrypt;
  final ARFSRepository _arfsRepository;

  ProfileFileDownloadCubit({
    required ARFSFileEntity file,
    required DriveDao driveDao,
    required ArweaveService arweave,
    required ArDriveDownloader downloader,
    required DownloadService downloadService,
    required Decrypt decrypt,
    required ARFSRepository arfsRepository,
  })  : _driveDao = driveDao,
        _arweave = arweave,
        _file = file,
        _downloader = downloader,
        _downloadService = downloadService,
        _arfsRepository = arfsRepository,
        _decrypt = decrypt,
        super(FileDownloadStarting());

  Future<void> download(SecretKey? cipherKey) async {
    try {
      final drive = await _arfsRepository.getDriveById(_file.driveId);
      final platform = SystemPlatform.platform;

      switch (drive.drivePrivacy) {
        case DrivePrivacy.private:
          if (platform == 'Android' || platform == 'iOS') {
            if (isSizeAbovePrivateLimit(_file.size)) {
              emit(const FileDownloadFailure(
                  FileDownloadFailureReason.fileAboveLimit));
              return;
            }

            if (state is! FileDownloadWarning &&
                isSizeAboveUploadTimeWarningLimit(_file.size)) {
              emit(const FileDownloadWarning());
              return;
            }
          }

          await _downloadFile(drive, cipherKey);
          break;
        case DrivePrivacy.public:
          if (platform == 'Android' || platform == 'iOS') {
            final stream = _downloader.downloadFile(
              '${_arweave.client.api.gatewayUrl.origin}/${_file.txId}',
              _file.name,
            );

            await for (int progress in stream) {
              if (state is FileDownloadAborted) {
                return;
              }

              emit(
                FileDownloadWithProgress(
                  fileName: _file.name,
                  progress: progress,
                  fileSize: _file.size,
                ),
              );
              _downloadProgress.sink.add(FileDownloadProgress(progress / 100));
            }

            emit(FileDownloadFinishedWithSuccess(fileName: _file.name));
            break;
          }
          await _downloadFile(drive, cipherKey);
          return;

        default:
      }
    } catch (err) {
      addError(err);
    }
  }

  Future<void> _downloadFile(
    ARFSDriveEntity drive,
    SecretKey? cipherKey,
  ) async {
    emit(
      FileDownloadInProgress(
        fileName: _file.name,
        totalByteCount: _file.size,
      ),
    );

    final dataBytes = await _downloadService.download(_file.txId);

    if (drive.drivePrivacy == DrivePrivacy.private) {
      SecretKey? driveKey;

      if (cipherKey != null) {
        driveKey = await _driveDao.getDriveKey(
          drive.driveId,
          cipherKey,
        );
      } else {
        driveKey = await _driveDao.getDriveKeyFromMemory(_file.driveId);
      }

      if (driveKey == null) {
        throw StateError('Drive Key not found');
      }

      final fileKey = await _driveDao.getFileKey(_file.id, driveKey);
      final dataTx = await (_arweave.getTransactionDetails(_file.txId));

      if (dataTx != null) {
        final decryptedData = await _decrypt.decryptTransactionData(
          dataTx,
          dataBytes,
          fileKey,
        );

        emit(
          FileDownloadSuccess(
            bytes: decryptedData,
            fileName: _file.name,
            mimeType: _file.contentType ?? lookupMimeType(_file.name),
            lastModified: _file.lastModifiedDate,
          ),
        );
        return;
      }
    }

    emit(
      FileDownloadSuccess(
        bytes: dataBytes,
        fileName: _file.name,
        mimeType: _file.contentType ?? lookupMimeType(_file.name),
        lastModified: _file.lastModifiedDate,
      ),
    );
  }

  @visibleForTesting
  bool isSizeAbovePrivateLimit(int size) {
    debugPrint(_privateFileLimit.toString());
    return size > _privateFileLimit;
  }

  @visibleForTesting
  bool isSizeAboveUploadTimeWarningLimit(int size) {
    return size > _warningDownloadTimeLimit;
  }

  @override
  Future<void> abortDownload() async {
    emit(FileDownloadAborted());
    await _downloader.cancelDownload();
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(
      const FileDownloadFailure(
        FileDownloadFailureReason.unknownError,
      ),
    );
    super.onError(error, stackTrace);

    debugPrint('Failed to download personal file: $error $stackTrace');
  }
}
