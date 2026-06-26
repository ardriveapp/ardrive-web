part of 'file_download_cubit.dart';

/// [SharedFileDownloadCubit] includes logic to allow a user to download files that
/// are shared with them without a login.
class SharedFileDownloadCubit extends FileDownloadCubit {
  final SecretKey? fileKey;
  final ARFSFileEntity revision;
  final ArweaveService _arweave;
  final ArDriveDownloader _arDriveDownloader;
  final Map<String, String>? _preloadedTags;

  SharedFileDownloadCubit({
    this.fileKey,
    required this.revision,
    required ArweaveService arweave,
    required ArDriveCrypto crypto,
    required ArDriveDownloader arDriveDownloader,
    Map<String, String>? preloadedTags,
  })  : _arweave = arweave,
        _arDriveDownloader = arDriveDownloader,
        _preloadedTags = preloadedTags,
        super(FileDownloadStarting()) {
    verifyUploadLimitationsAndDownload();
  }

  // TODO: we are duplicating code here, we should refactor this. Personal and Share file downloads are pretty similar
  // we must refactor to reuse the code and avoid duplication
  Future<void> verifyUploadLimitationsAndDownload() async {
    if (await AppPlatform.isSafari()) {
      if (revision.size > publicDownloadSafariSizeLimit) {
        emit(const FileDownloadFailure(
            FileDownloadFailureReason.browserDoesNotSupportLargeDownloads));
        return;
      }
    }

    download();
  }

  Future<void> download() async {
    _downloadFile(revision).catchError((err) {
      logger.e(
        'Failed to download shared file ${revision.id} with name ${revision.name} (size: ${revision.size})',
        err,
      );
      addError(err);
    });
  }

  Future<void> _downloadFile(ARFSFileEntity revision) async {
    emit(
      FileDownloadInProgress(
        fileName: revision.name,
        totalByteCount: revision.size,
      ),
    );

    String? cipherTag;
    String? cipherIvTag;
    final isPinFile = revision.pinnedDataOwnerAddress != null;

    final dataTxId = revision.dataTxId;

    if (dataTxId == null) {
      throw StateError(
          'Data transaction id is null for file ${revision.id} with name ${revision.name}');
    }

    // Use preloaded tags if available (from SharedFileCubit's initial fetch),
    // otherwise query the network.
    Map<String, String>? tags = _preloadedTags;
    if (tags == null) {
      final dataTx = await _arweave.getTransactionDetails(dataTxId);
      if (dataTx == null) {
        throw StateError(
            'Data transaction not found for file ${revision.id} with txId $dataTxId from gateway ${_arweave.client.api.gatewayUrl.origin}');
      }
      tags = {for (final tag in dataTx.tags) tag.name: tag.value};
    }

    if (fileKey != null && !isPinFile) {
      cipherTag = tags[EntityTag.cipher];
      cipherIvTag = tags[EntityTag.cipherIv];
    }

    logger.d('File size: ${revision.size}');

    final downloadStream = await _arDriveDownloader.downloadFile(
      dataTxId: dataTxId,
      appName: tags[EntityTag.appName],
      fileName: revision.name,
      fileSize: revision.size,
      lastModifiedDate: revision.lastModifiedDate,
      contentType:
          revision.contentType ?? lookupMimeTypeWithDefaultType(revision.name),
      cipher: cipherTag,
      cipherIvString: cipherIvTag,
      fileKey: fileKey,
      isManifest: revision.contentType == ContentType.manifest,
    );

    downloadStream.listen(
      (progress) {
        logger.d('Download progress: $progress');

        if (state is FileDownloadAborted) {
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
      },
      onError: (err) {
        addError(err);
      },
      onDone: () {
        logger.d('Download finished');
        emit(FileDownloadFinishedWithSuccess(fileName: revision.name));
      },
      cancelOnError: true,
    );
  }

  @override
  void abortDownload() {
    emit(FileDownloadAborted());
    _arDriveDownloader.abortDownload();
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(const FileDownloadFailure(FileDownloadFailureReason.unknownError));
    super.onError(error, stackTrace);

    logger.e(
      'Failed to download shared file ${revision.id} with txId ${revision.dataTxId} from gateway ${_arweave.client.api.gatewayUrl.origin}. File name: ${revision.name}, size: ${revision.size}',
      error,
      stackTrace,
    );
  }
}
