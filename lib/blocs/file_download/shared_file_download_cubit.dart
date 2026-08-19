part of 'file_download_cubit.dart';

/// [SharedFileDownloadCubit] includes logic to allow a user to download files that
/// are shared with them without a login.
class SharedFileDownloadCubit extends FileDownloadCubit {
  final SecretKey? fileKey;
  final ARFSFileEntity revision;
  final ArweaveService _arweave;
  final ArDriveDownloader _arDriveDownloader;
  final DownloadPolicy _downloadPolicy;

  /// The cipher the share link named, when it named one.
  ///
  /// Supplied only for a transaction the caller knows is bundled - see
  /// `_downloadFile` for why that qualification is load bearing.
  final String? cipher;

  /// The cipher IV the share link named. Travels with [cipher] or not at all.
  final String? cipherIv;

  SharedFileDownloadCubit({
    this.fileKey,
    this.cipher,
    this.cipherIv,
    required this.revision,
    required ArweaveService arweave,
    required ArDriveCrypto crypto,
    required ArDriveDownloader arDriveDownloader,
    DownloadPolicy downloadPolicy = const DownloadPolicy(),
  })  : _arweave = arweave,
        _arDriveDownloader = arDriveDownloader,
        _downloadPolicy = downloadPolicy,
        super(FileDownloadStarting()) {
    watchForReconnects(_arDriveDownloader);
    verifyUploadLimitationsAndDownload();
  }

  // TODO: we are duplicating code here, we should refactor this. Personal and Share file downloads are pretty similar
  // we must refactor to reuse the code and avoid duplication
  Future<void> verifyUploadLimitationsAndDownload() async {
    try {
      // One decision, one place (F22) — see [DownloadPolicy.singleFileLimit].
      final limit = await _downloadPolicy.singleFileLimit(
        isPublic: fileKey == null,
      );

      final failure = singleFileLimitFailure(limit, revision.size);
      if (failure != null) {
        emit(FileDownloadFailure(failure));
        return;
      }
    } catch (e) {
      // This runs from the constructor with its future discarded, so an
      // unhandled error here would leave the dialog on [FileDownloadStarting]
      // for ever. [DownloadPolicy.singleFileLimit] reaches the device info
      // platform channel to recognise Safari, and a channel that is not there
      // must cost a size *check*, never the download. Same posture as
      // [ProfileFileDownloadCubit.verifyUploadLimitationsAndDownload].
      logger.d(
        'Could not check the download size limit for shared file '
        '${revision.id}; proceeding with the download. Error: $e',
      );
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
    bool verifyDownload = false;
    final isPinFile = revision.pinnedDataOwnerAddress != null;

    final dataTxId = revision.dataTxId;

    if (dataTxId == null) {
      throw StateError(
          'Data transaction id is null for file ${revision.id} with name ${revision.name}');
    }

    if (fileKey != null && !isPinFile) {
      if (cipher != null && cipherIv != null) {
        // The link already said what this transaction is encrypted with, so
        // the lookup that would have asked is skipped entirely. Carrying `c`
        // and `iv` in a share link only pays for itself here - before this,
        // every private download re-fetched tags the link had already
        // delivered, which on a rate-limited connection is a call that can
        // fail outright.
        //
        // `verifyDownload` stays false, and correctly so: it turns on the
        // arweave client's chunk check for L1 transactions, and the caller
        // only supplies these tags for a data item it knows is bundled -
        // which is not an L1 transaction and has no chunks to check.
        cipherTag = cipher;
        cipherIvTag = cipherIv;
      } else {
        // Private/encrypted files need cipher/IV tags from the data transaction
        final dataTx = await _arweave.getTransactionDetails(dataTxId);

        if (dataTx == null) {
          throw StateError(
              'Data transaction not found for file ${revision.id} with txId $dataTxId from gateway ${_arweave.client.api.gatewayUrl.origin}');
        }

        cipherTag = dataTx.getTag(EntityTag.cipher);
        cipherIvTag = dataTx.getTag(EntityTag.cipherIv);
        verifyDownload = dataTx.getTag(EntityTag.appName) == 'ArDrive-CLI';
      }
    }

    logger.d('File size: ${revision.size}');

    final downloadStream = await _arDriveDownloader.downloadFile(
      txId: dataTxId,
      fileName: revision.name,
      fileSize: revision.size,
      lastModifiedDate: revision.lastModifiedDate,
      contentType:
          revision.contentType ?? lookupMimeTypeWithDefaultType(revision.name),
      cipher: cipherTag,
      cipherIvString: cipherIvTag,
      fileKey: fileKey,
      isManifest: revision.contentType == ContentType.manifest,
      verifyDownload: verifyDownload,
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

        // The bytes are on disk; only now is it safe to wait on the verdict.
        unawaited(emitFinishedWithIntegrity(
          downloader: _arDriveDownloader,
          fileName: revision.name,
        ));
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
  FutureOr<void> retryDownload() {
    emit(FileDownloadStarting());
    download();
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    final reason = classifyDownloadError(error);
    emit(FileDownloadFailure(reason));
    super.onError(error, stackTrace);

    logger.e(
      'Failed to download shared file ${revision.id} with txId '
      '${revision.dataTxId} (reason: $reason)',
      error,
      stackTrace,
    );
  }
}
