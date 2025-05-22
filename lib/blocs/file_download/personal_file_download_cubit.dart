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
  final io.ArDriveMobileDownloader _downloader;
  final ArDriveDownloader _arDriveDownloader;
  final ARFSRepository _arfsRepository;

  ProfileFileDownloadCubit({
    required ARFSFileEntity file,
    required DriveDao driveDao,
    required ArweaveService arweave,
    required io.ArDriveMobileDownloader downloader,
    required ArDriveDownloader arDriveDownloader,
    required ARFSRepository arfsRepository,
    required ArDriveCrypto crypto,
  })  : _driveDao = driveDao,
        _arweave = arweave,
        _arDriveDownloader = arDriveDownloader,
        _file = file,
        _downloader = downloader,
        _arfsRepository = arfsRepository,
        super(FileDownloadStarting());

  Future<void> verifyUploadLimitationsAndDownload(SecretKey? cipherKey) async {
    try {
      if (await AppPlatform.isSafari()) {
        if (_file.size > publicDownloadSafariSizeLimit) {
          emit(const FileDownloadFailure(
              FileDownloadFailureReason.browserDoesNotSupportLargeDownloads));
          return;
        }
      }
    } catch (e) {
      logger.d(
          'Error verifying upload limitations and downloading file... proceeding with download');
    }

    download(cipherKey);
  }

  Future<void> download(SecretKey? cipherKey) async {
    try {
      final drive = await _arfsRepository.getDriveById(_file.driveId);

      switch (drive.drivePrivacy) {
        case DrivePrivacy.private:
          if (AppPlatform.isMobile) {
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

          final isPinFile = _file.pinnedDataOwnerAddress != null;

          if (isPinFile) {
            await _downloadFile(drive, null);
          } else {
            await _downloadFile(drive, cipherKey);
          }

          break;
        case DrivePrivacy.public:
          if (AppPlatform.isMobile) {
            final stream = _downloader.downloadFile(
              '${_arweave.client.api.gatewayUrl.origin}/${_file.txId}',
              _file.name,
              _file.contentType,
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
                  contentType: _file.contentType ??
                      lookupMimeTypeWithDefaultType(_file.name),
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

    logger.d('Downloading file...');

    String? cipher;
    String? cipherIvTag;
    SecretKey? fileKey;

    final isPinFile = _file.pinnedDataOwnerAddress != null;

    final dataTx = await (_arweave.getTransactionDetails(_file.txId));

    if (dataTx == null) {
      throw StateError(
          'Failed to download: Data transaction not found for file');
    }

    if (drive.drivePrivacy == DrivePrivacy.private && !isPinFile) {
      DriveKey? driveKey;

      if (cipherKey != null) {
        driveKey = await _driveDao.getDriveKey(
          drive.driveId,
          cipherKey,
        );
      } else {
        driveKey = await _driveDao.getDriveKeyFromMemory(_file.driveId);
      }

      if (driveKey == null) {
        throw StateError(
            'Drive Key not found for file ${_file.id} in drive ${_file.driveId}');
      }

      fileKey = await _driveDao.getFileKey(_file.id, driveKey.key);

      cipher = dataTx.getTag(EntityTag.cipher);
      cipherIvTag = dataTx.getTag(EntityTag.cipherIv);
    }

    // log file size
    logger.d('File size: ${_file.size}');

    final downloadStream = await _arDriveDownloader.downloadFile(
      dataTx: dataTx,
      fileName: _file.name,
      fileSize: _file.size,
      lastModifiedDate: _file.lastModifiedDate,
      isManifest: _file.contentType == ContentType.manifest,
      contentType:
          _file.contentType ?? lookupMimeTypeWithDefaultType(_file.name),
      cipher: cipher,
      cipherIvString: cipherIvTag,
      fileKey: fileKey,
    );

    downloadStream.listen(
      (progress) {
        logger.d('Download progress: $progress');

        if (state is FileDownloadAborted) {
          return;
        }

        emit(
          FileDownloadWithProgress(
            fileName: _file.name,
            progress: progress.toInt(),
            fileSize: _file.size,
            contentType:
                _file.contentType ?? lookupMimeTypeWithDefaultType(_file.name),
          ),
        );

        _downloadProgress.sink.add(FileDownloadProgress(progress / 100));
      },
      onError: (e) {
        if (e is DownloadCancelledException) {
          emit(FileDownloadAborted());
        } else {
          addError(e);
        }
      },
      onDone: () {
        emit(FileDownloadFinishedWithSuccess(fileName: _file.name));
      },
      cancelOnError: true,
    );
  }

  @visibleForTesting
  bool isSizeAbovePrivateLimit(int size) {
    return size > _privateFileLimit;
  }

  @visibleForTesting
  bool isSizeAboveUploadTimeWarningLimit(int size) {
    return size > _warningDownloadTimeLimit;
  }

  @override
  Future<void> abortDownload() async {
    emit(FileDownloadAborted());
    final drive = await _arfsRepository.getDriveById(_file.driveId);

    if (drive.drivePrivacy == DrivePrivacy.private) {
      await _downloader.cancelDownload();
    }
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(
      const FileDownloadFailure(
        FileDownloadFailureReason.unknownError,
      ),
    );

    super.onError(error, stackTrace);

    logger.e(
      'Failed to download file ${_file.id} with txId ${_file.txId} from gateway ${_arweave.client.api.gatewayUrl.origin}',
      error,
      stackTrace,
    );
  }
}
