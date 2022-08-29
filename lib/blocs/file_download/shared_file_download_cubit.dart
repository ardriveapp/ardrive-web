part of 'file_download_cubit.dart';

/// [SharedFileDownloadCubit] includes logic to allow a user to download files that
/// are shared with them without a login.
class SharedFileDownloadCubit extends FileDownloadCubit {
  final String fileId;
  final SecretKey? fileKey;

  final ArweaveService _arweave;

  SharedFileDownloadCubit({
    required this.fileId,
    this.fileKey,
    required ArweaveService arweave,
  })  : _arweave = arweave,
        super(FileDownloadStarting()) {
    download();
  }

  Future<void> download() async {
    try {
      final file = _validateDownload(
          (await _arweave.getLatestFileEntityWithId(fileId, fileKey)));

      /// We can use the ! operator because we already validated on `_validateDownload`

      emit(FileDownloadInProgress(
          fileName: file.name!, totalByteCount: file.size!));
      //Reinitialize here in case connection is closed with abort

      final dataRes = await http.get(Uri.parse(
          '${_arweave.client.api.gatewayUrl.origin}/${file.dataTxId}'));

      Uint8List dataBytes;

      if (fileKey == null) {
        dataBytes = dataRes.bodyBytes;
      } else {
        final dataTx = (await _arweave.getTransactionDetails(file.dataTxId!))!;
        dataBytes =
            await decryptTransactionData(dataTx, dataRes.bodyBytes, fileKey!);
      }

      emit(
        FileDownloadSuccess(
          bytes: dataBytes,
          fileName: file.name!,
          mimeType: lookupMimeType(file.name!),
          lastModified: file.lastModifiedDate!,
        ),
      );
    } catch (err) {
      addError(err);
    }
  }

  FileEntity _validateDownload(FileEntity? file) {
    if (file == null ||
        file.name == null ||
        file.lastModifiedDate == null ||
        file.dataTxId == null ||
        file.size == null) {
      throw Exception('Malformed FileEntity to download');
    }

    return file;
  }

  @override
  void abortDownload() {
    emit(FileDownloadAborted());
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(FileDownloadFailure());
    super.onError(error, stackTrace);

    print('Failed to download shared file: $error $stackTrace');
  }
}
