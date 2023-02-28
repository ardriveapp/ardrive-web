part of 'file_download_cubit.dart';

/// [ProfileFileDownloadCubit] includes logic to allow a user to download files
/// that they have attached to their profile.
class FileDownloadProgress extends LinearProgress {
  @override
  final double progress;

  FileDownloadProgress(this.progress);
}

class StreamPersonalFileDownloadCubit extends FileDownloadCubit {
  final ARFSFileEntity _file;

  final _warningDownloadTimeLimit = const MiB(200).size;

  final Completer<String> _cancelWithReason = Completer<String>();

  final DriveDao _driveDao;
  final ArweaveService _arweave;
  final ArDriveDownloader _downloader;
  final DownloadService _downloadService;
  final Decrypt _decrypt;
  final ARFSRepository _arfsRepository;
  final ArDriveIO _ardriveIo;
  final IOFileAdapter _ioFileAdapter;
  final Authenticate _authenticate;

  StreamPersonalFileDownloadCubit({
    required ARFSFileEntity file,
    required DriveDao driveDao,
    required ArweaveService arweave,
    required ArDriveDownloader downloader,
    required DownloadService downloadService,
    required Decrypt decrypt,
    required ARFSRepository arfsRepository,
    required ArDriveIO ardriveIo,
    required IOFileAdapter ioFileAdapter,
    required Authenticate authenticate,
  })  : _driveDao = driveDao,
        _arweave = arweave,
        _file = file,
        _downloader = downloader,
        _downloadService = downloadService,
        _arfsRepository = arfsRepository,
        _decrypt = decrypt,
        _ardriveIo = ardriveIo,
        _ioFileAdapter = ioFileAdapter,
        _authenticate = authenticate,
        super(FileDownloadStarting());

  Future<void> download(SecretKey? cipherKey) async {
    try {
      final drive = await _arfsRepository.getDriveById(_file.driveId);

      switch (drive.drivePrivacy) {
        case DrivePrivacy.private:
          if (AppPlatform.isMobile) {
            if (state is! FileDownloadWarning &&
                isSizeAboveUploadTimeWarningLimit(_file.size)) {
              emit(const FileDownloadWarning());
              return;
            }
          }

          await _downloadFile(drive, cipherKey);
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
                ),
              );
              downloadProgressController.sink.add(FileDownloadProgress(progress / 100));
            }

            emit(FileDownloadFinishedWithSuccess(fileName: _file.name));
          } else {
            await _downloadFile(drive, cipherKey);
          }
          break;

        default:
          throw Exception('Unknown drive privacy: ${drive.drivePrivacy}');
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
    
    final dataTx = (await _arweave.getTransactionDetails(_file.txId))!;
    final downloadLength = int.parse(dataTx.data.size);
    
    final fetchStream = _downloadService.downloadStream(
      _file.txId,
      downloadLength,
      cancelWithReason: _cancelWithReason,
    );

    final splitStream = StreamSplitter(fetchStream);
    final saveStream = splitStream.split();
    final authStream = splitStream.split();

    // Calling `close()` indicates that no further streams will be created,
    // causing splitStream to function without an internal buffer.
    // The future will be completed when both streams are consumed, so we
    // shouldn't await it here.
    unawaited(splitStream.close());

    Stream<Uint8List> saveStreamDecrypted;
    if (drive.drivePrivacy == DrivePrivacy.public) {
      saveStreamDecrypted = saveStream;
    } else if (drive.drivePrivacy == DrivePrivacy.private) {
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

      saveStreamDecrypted = await _decrypt.decryptTransactionDataStream(
        dataTx,
        saveStream,
        Uint8List.fromList(await fileKey.extractBytes()),
      );
    } else {
      throw Exception('Invalid drive privacy');
    }

    final file = await _ioFileAdapter.fromReadStreamGenerator(
      ([s, e]) => saveStreamDecrypted,
      _file.size,
      name: _file.name,
      lastModifiedDate: _file.lastModifiedDate
    );

    try {
      final authenticatedOwner = _authenticate.authenticateOwner(
        authStream,
        downloadLength,
        _file.txId,
        dataTx,
      );
      final finalize = Completer<bool>();
      Future.any([
        _cancelWithReason.future.then((_) => false),
        authenticatedOwner.then((owner) => owner != null),
      ]).then((value) => finalize.complete(value));

      bool? saveResult;
      await for (final saveStatus in _ardriveIo.saveFileStream(file, finalize)) {
        if (saveStatus.saveResult == null) {
          if (saveStatus.bytesSaved == 0) continue;

          final progress = saveStatus.bytesSaved / saveStatus.totalBytes;
          downloadProgressController.sink.add(FileDownloadProgress(progress));

          final progressPercentInt = (progress * 100).round();
          emit(FileDownloadWithProgress(
            fileName: _file.name,
            progress: progressPercentInt,
            fileSize: saveStatus.totalBytes,
          ));
        } else {
          saveResult = saveStatus.saveResult!;
        }
      }

      if (_cancelWithReason.isCompleted) throw Exception('Download cancelled: ${await _cancelWithReason.future}');
      if (await authenticatedOwner == null) throw Exception('Failed authentication');
      if (saveResult != true) throw Exception('Failed to save file');

      emit(
        FileDownloadFinishedWithSuccess(
          fileName: _file.name,
          authenticatedOwner: await authenticatedOwner,
        ),
      );
    } on Exception catch (e) {
      emit(
        const FileDownloadFailure(
          FileDownloadFailureReason.unknownError,
        ),
      );
      debugPrint('Failed to download personal file: $e');
      return;
    }
  }

  @visibleForTesting
  bool isSizeAboveUploadTimeWarningLimit(int size) {
    return size > _warningDownloadTimeLimit;
  }

  @override
  Future<void> abortDownload() async {
    _cancelWithReason.complete('Aborted by user');

    emit(FileDownloadAborted());

    final drive = await _arfsRepository.getDriveById(_file.driveId);
    if (drive.drivePrivacy == DrivePrivacy.private && AppPlatform.isMobile) {
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

    debugPrint('Failed to download personal file: $error $stackTrace');
  }
}
