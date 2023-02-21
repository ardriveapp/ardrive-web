part of 'file_download_cubit.dart';

/// [StreamSharedFileDownloadCubit] includes logic to allow a user to download files that
/// are shared with them without a login.
class StreamSharedFileDownloadCubit extends FileDownloadCubit {
  final SecretKey? fileKey;
  final FileRevision revision;
  final ArweaveService _arweave;
  final DownloadService _downloadService;
  final Decrypt _decrypt;
  final ArDriveIO _ardriveIo;
  final IOFileAdapter _ioFileAdapter;

  StreamSharedFileDownloadCubit({
    this.fileKey,
    required this.revision,
    required ArweaveService arweave,
    required DownloadService downloadService,
    required Decrypt decrypt,
    required ArDriveIO ardriveIo,
    required IOFileAdapter ioFileAdapter,
  })  : _arweave = arweave,
        _downloadService = downloadService,
        _decrypt = decrypt,
        _ardriveIo = ardriveIo,
        _ioFileAdapter = ioFileAdapter,
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
    emit(
      FileDownloadInProgress(
        fileName: revision.name,
        totalByteCount: revision.size,
      ),
    );

    final fetchStream = _downloadService.downloadStream(revision.dataTxId, revision.size);
    final splitStream = StreamSplitter(fetchStream);
    final authStream = splitStream.split();
    unawaited(splitStream.close());

    Stream<Uint8List> decryptedDataStream;
    if (fileKey == null) {
      decryptedDataStream = splitStream.split();
    } else {
      final dataTx = await (_arweave.getTransactionDetails(revision.dataTxId));

      decryptedDataStream = await _decrypt.decryptTransactionDataStream(
        dataTx!,
        splitStream.split(),
        Uint8List.fromList(await fileKey!.extractBytes()),
      );
    }

    final file = await _ioFileAdapter.fromReadStreamGenerator(
      ([s, e]) => decryptedDataStream,
      revision.size,
      name: revision.name,
      lastModifiedDate: revision.lastModifiedDate
    );

    try {
      final transaction = await _arweave.getTransaction<TransactionStream>(revision.dataTxId);
      if (transaction == null) throw Exception('Failed to get transaction');
      
      Future<bool> authenticate() async {
        try {
          await transaction.processDataStream(authStream, revision.size);
        } catch (e) {
          return false;
        }
        return await transaction.verify();
      }

      final saved = await _ardriveIo.saveFileStream(file, authenticate());
      if (!saved) throw Exception('Failed to save file');

      emit(
        FileDownloadFinishedWithSuccess(
          fileName: revision.name,
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
