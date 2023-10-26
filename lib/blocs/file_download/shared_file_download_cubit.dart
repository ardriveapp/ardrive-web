part of 'file_download_cubit.dart';

/// [SharedFileDownloadCubit] includes logic to allow a user to download files that
/// are shared with them without a login.
class SharedFileDownloadCubit extends FileDownloadCubit {
  final SecretKey? fileKey;
  final ARFSFileEntity revision;
  final ArweaveService _arweave;
  final ArDriveDownloader _arDriveDownloader;

  SharedFileDownloadCubit({
    this.fileKey,
    required this.revision,
    required ArweaveService arweave,
    required ArDriveCrypto crypto,
    required ArDriveDownloader arDriveDownloader,
  })  : _arweave = arweave,
        _arDriveDownloader = arDriveDownloader,
        super(FileDownloadStarting()) {
    download();
  }

  Future<void> download() async {
    try {
      _downloadFile(revision);
    } catch (err) {
      addError(err);
    }
  }

  Future<void> _downloadFile(ARFSFileEntity revision) async {
    emit(
      FileDownloadInProgress(
        fileName: revision.name,
        totalByteCount: revision.size,
      ),
    );

    String? cipher;
    String? cipherIvTag;
    final isPinFile = revision.pinnedDataOwnerAddress != null;

    if (revision.dataTxId == null) {
      logger.e('Data transaction id is null');
      throw StateError('Data transaction id is null');
    }

    if (fileKey != null && !isPinFile) {
      final dataTx = await _arweave.getTransactionDetails(revision.dataTxId!);

      if (dataTx == null) {
        throw StateError('Data transaction not found');
      }

      cipher = dataTx.getTag(EntityTag.cipher);
      cipherIvTag = dataTx.getTag(EntityTag.cipherIv);
    }

    final downloadStream = _arDriveDownloader.downloadFile(
      dataTx: revision.dataTxId!,
      fileName: revision.name,
      fileSize: revision.size,
      lastModifiedDate: revision.lastModifiedDate,
      contentType:
          revision.contentType ?? lookupMimeTypeWithDefaultType(revision.name),
      cipher: cipher,
      cipherIvString: cipherIvTag,
      fileKey: fileKey,
      isManifest: revision.contentType == ContentType.manifest,
    );

    logger.d(
        'Downloading file ${revision.name} and dataTxId is ${revision.txId} of size ${revision.size}');

    await for (var progress in downloadStream) {
      if (state is FileDownloadAborted) {
        return;
      }

      if (progress == 100) {
        emit(FileDownloadFinishedWithSuccess(fileName: revision.name));
        logger.d('Download finished');
        return;
      }

      emit(
        FileDownloadWithProgress(
          fileName: revision.name,
          progress: progress.toInt(),
          fileSize: revision.size,
          contentType: revision.contentType ??
              lookupMimeTypeWithDefaultType(revision.name),
        ),
      );
    }

    logger.d('Download finished');

    emit(FileDownloadFinishedWithSuccess(fileName: revision.name));
  }

  @override
  void abortDownload() {
    emit(FileDownloadAborted());
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(const FileDownloadFailure(FileDownloadFailureReason.unknownError));
    super.onError(error, stackTrace);

    logger.e('Failed to download shared file', error, stackTrace);
  }
}
