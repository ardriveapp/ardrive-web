part of 'file_download_cubit.dart';

/// [SharedFileDownloadCubit] includes logic to allow a user to download files that
/// are shared with them without a login.
class SharedFileDownloadCubit extends FileDownloadCubit {
  final SecretKey? fileKey;
  final FileRevision revision;
  final ArweaveService _arweave;
  final ArDriveCrypto _crypto;

  SharedFileDownloadCubit({
    this.fileKey,
    required this.revision,
    required ArweaveService arweave,
    required ArDriveCrypto crypto,
  })  : _arweave = arweave,
        _crypto = crypto,
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

  Future<void> _downloadFile(FileRevision revision) async {
    late Uint8List dataBytes;

    emit(
      FileDownloadInProgress(
        fileName: revision.name,
        totalByteCount: revision.size,
      ),
    );

    final dataRes = await ArDriveHTTP().getAsBytes(
        '${_arweave.client.api.gatewayUrl.origin}/${revision.dataTxId}');

    if (fileKey != null) {
      final dataTx = await (_arweave.getTransactionDetails(revision.dataTxId));

      if (dataTx != null) {
        dataBytes = await _crypto.decryptTransactionData(
          dataTx,
          dataRes.data,
          fileKey!,
        );
      }
    } else {
      dataBytes = dataRes.data;
    }

    emit(
      FileDownloadSuccess(
        bytes: dataBytes,
        fileName: revision.name,
        mimeType: revision.dataContentType ?? lookupMimeType(revision.name),
        lastModified: revision.lastModifiedDate,
      ),
    );
  }

  @override
  void abortDownload() {
    emit(FileDownloadAborted());
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(const FileDownloadFailure(FileDownloadFailureReason.unknownError));
    super.onError(error, stackTrace);

    log('Failed to download shared file: $error $stackTrace');
  }
}
