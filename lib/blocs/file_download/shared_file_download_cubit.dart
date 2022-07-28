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
      final file = (await _arweave.getLatestFileEntityWithId(fileId, fileKey))!;

      emit(FileDownloadInProgress(
          fileName: file.name!, totalByteCount: file.size!));
      //Reinitialize here in case connection is closed with abort

      final dataRes = await http.get(Uri.parse(
          _arweave.client.api.gatewayUrl.origin + '/${file.dataTxId}'));

      Uint8List dataBytes;

      if (fileKey == null) {
        dataBytes = dataRes.bodyBytes;
      } else {
        final dataTx = (await _arweave.getTransactionDetails(file.dataTxId!))!;
        dataBytes =
            await decryptTransactionData(dataTx, dataRes.bodyBytes, fileKey!);
      }

      /// TODO(@thiagocarvalhodev): how handle null and empty data here?
      emit(
        FileDownloadSuccess(
          bytes: dataBytes,
          fileName: file.name ?? '',
          mimeType: lookupMimeType(file.name!),
          lastModified: file.lastModifiedDate ?? DateTime.now(),
        ),
      );
    } catch (err) {
      addError(err);
    }
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
