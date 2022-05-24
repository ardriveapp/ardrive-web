part of 'file_download_cubit.dart';

/// [ProfileFileDownloadCubit] includes logic to allow a user to download files
/// that they have attached to their profile.
class ProfileFileDownloadCubit extends FileDownloadCubit {
  final DriveID driveId;
  final FileID fileId;
  final TxID dataTxId;

  final ProfileCubit _profileCubit;
  final DriveDao _driveDao;
  final ArweaveService _arweave;

  ProfileFileDownloadCubit({
    required this.driveId,
    required this.fileId,
    required this.dataTxId,
    required ProfileCubit profileCubit,
    required DriveDao driveDao,
    required ArweaveService arweave,
  })  : _profileCubit = profileCubit,
        _driveDao = driveDao,
        _arweave = arweave,
        super(FileDownloadStarting()) {
    download();
  }

  Future<void> download() async {
    try {
      final drive = await _driveDao.driveById(driveId: driveId).getSingle();
      final file = await _driveDao
          .fileById(driveId: driveId, fileId: fileId)
          .getSingle();

      emit(
        FileDownloadInProgress(
          fileName: file.name,
          totalByteCount: file.size,
        ),
      );
      late Uint8List dataBytes;

      // final client = http.Client();
      // final request = http.Request(
      //   'GET',
      //   Uri.parse(
      //     _arweave.client.api.gatewayUrl.origin + '/$dataTxId',
      //   ),
      // );

      final buffer = await downloadProgress(dataTxId, _arweave);
      // final response = await client.send(request);
      // // final stream = response.stream;
      // List<int> buffer = [];
      // var total = response.contentLength ?? 0;

      // response.stream.listen((value) {
      //   buffer.addAll(value);
      //   print(total);
      //   total += value.length;
      // }).onDone(() async {
      //   print('done');
      // });

      print(buffer.length); 

      // final dataRes = await http.get(
      //   Uri.parse(
      //     _arweave.client.api.gatewayUrl.origin + '/$dataTxId',
      //   ),
      // );

      switch (drive.privacy) {
        case DrivePrivacy.private:
          final profile = _profileCubit.state;
          SecretKey? driveKey;

          if (profile is ProfileLoggedIn) {
            driveKey = await _driveDao.getDriveKey(
              drive.id,
              profile.cipherKey,
            );
          } else {
            driveKey = await _driveDao.getDriveKeyFromMemory(driveId);
          }

          if (driveKey == null) {
            throw StateError('Drive Key not found');
          }

          final fileKey = await _driveDao.getFileKey(fileId, driveKey);
          final dataTx = await (_arweave.getTransactionDetails(file.dataTxId));

          if (dataTx != null) {
            dataBytes = await decryptTransactionData(
              dataTx,
              Uint8List.fromList(buffer),
              fileKey,
            );
          }

          break;
        case DrivePrivacy.public:
          dataBytes = Uint8List.fromList(buffer);
          break;
        default:
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
    emit(FileDownloadAborted());
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(FileDownloadFailure());
    super.onError(error, stackTrace);

    print('Failed to download personal file: $error $stackTrace');
  }
}
