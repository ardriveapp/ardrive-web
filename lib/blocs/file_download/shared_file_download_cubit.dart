part of 'file_download_cubit.dart';

/// [SharedFileDownloadCubit] includes logic to allow a user to download files that
/// are shared with them without a login.
class SharedFileDownloadCubit extends FileDownloadCubit {
  final String fileId;
  final SecretKey fileKey;

  final ArweaveService _arweave;

  HttpRequest _httpRequestClient;

  SharedFileDownloadCubit({
    @required this.fileId,
    this.fileKey,
    @required ArweaveService arweave,
  })  : _arweave = arweave,
        _httpRequestClient = HttpRequest(),
        super(FileDownloadStarting()) {
    download();
  }

  Future<void> download() async {
    try {
      final file = await _arweave.getLatestFileEntityWithId(fileId, fileKey);

      emit(FileDownloadInProgress(
          fileName: file.name, totalByteCount: file.size));
      //Reinitialize here in case connection is closed with abort
      _httpRequestClient = HttpRequest();
      final dataRes = await _httpRequestClient.open(
          'GET', _arweave.client.api.gatewayUrl.origin + '/${file.dataTxId}');

      Uint8List dataBytes;
      print(_httpRequestClient.response);
      if (fileKey == null) {
        dataBytes = _httpRequestClient.response;
      } else {
        final dataTx = await _arweave.getTransactionDetails(file.dataTxId);
        dataBytes = await decryptTransactionData(
            dataTx, _httpRequestClient.response, fileKey);
      }

      emit(
        FileDownloadSuccess(
          file: XFile.fromData(
            dataBytes,
            name: file.name,
            mimeType: lookupMimeType(file.name),
            length: dataBytes.lengthInBytes,
            lastModified: file.lastModifiedDate,
          ),
        ),
      );
    } catch (err) {
      addError(err);
    }
  }

  @override
  void abortDownload() {
    _httpRequestClient.abort();
    emit(FileDownloadAborted());
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(FileDownloadFailure());
    super.onError(error, stackTrace);

    print('Failed to download shared file: $error $stackTrace');
  }
}
