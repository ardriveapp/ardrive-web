part of 'file_download_cubit.dart';

/// [SharedFileDownloadCubit] includes logic to allow a user to download files that
/// are shared with them without a login.
class SharedFileDownloadCubit extends FileDownloadCubit {
  final String fileId;
  final SecretKey fileKey;

  final ArweaveService _arweave;

  SharedFileDownloadCubit({
    @required this.fileId,
    this.fileKey,
    @required ArweaveService arweave,
  })  : _arweave = arweave,
        super(FileDownloadStarting()) {
    download();
  }

  Future<void> download() async {
    try {
      final file = await _arweave.tryGetLatestFileEntityWithId(fileId, fileKey);

      emit(FileDownloadInProgress(
          fileName: file.name, totalByteCount: file.size));

      final dataRes = await http
          .get(_arweave.client.api.gatewayUrl.origin + '/${file.dataTxId}');

      Uint8List dataBytes;

      if (fileKey == null) {
        dataBytes = dataRes.bodyBytes;
      } else {
        final dataTx = await _arweave.getTransactionDetails(file.dataTxId);
        dataBytes =
            await decryptTransactionData(dataTx, dataRes.bodyBytes, fileKey);
      }

      emit(
        FileDownloadSuccess(
          fileName: file.name,
          fileExtension: extension(file.name),
          fileDataBytes: dataBytes,
        ),
      );
    } catch (err) {
      addError(err);
    }
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(FileDownloadFailure());
    super.onError(error, stackTrace);
  }
}
