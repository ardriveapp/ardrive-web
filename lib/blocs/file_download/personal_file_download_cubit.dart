part of 'file_download_cubit.dart';

/// [ProfileFileDownloadCubit] includes logic to allow a user to download files
/// that they have attached to their profile.
class ProfileFileDownloadCubit extends FileDownloadCubit {
  final String driveId;
  final String fileId;

  final ProfileCubit _profileCubit;
  final DriveDao _driveDao;
  final ArweaveService _arweave;

  Dio _dioClient;

  ProfileFileDownloadCubit({
    @required this.driveId,
    @required this.fileId,
    @required ProfileCubit profileCubit,
    @required DriveDao driveDao,
    @required ArweaveService arweave,
  })  : _profileCubit = profileCubit,
        _driveDao = driveDao,
        _arweave = arweave,
        _dioClient = Dio(),
        super(FileDownloadStarting()) {
    download();
  }

  Future<void> download() async {
    try {
      final drive = await _driveDao.driveById(driveId: driveId).getSingle();
      final file = await _driveDao
          .fileById(driveId: driveId, fileId: fileId)
          .getSingle();

      emit(FileDownloadInProgress(
          fileName: file.name, totalByteCount: file.size));
      _dioClient = Dio();
      final dataRes = await _dioClient
          .get(_arweave.client.api.gatewayUrl.origin + '/${file.dataTxId}');

      Uint8List dataBytes;

      if (drive.isPublic) {
        dataBytes = dataRes.data;
      } else if (drive.isPrivate) {
        final profile = _profileCubit.state as ProfileLoggedIn;

        final dataTx = await _arweave.getTransactionDetails(file.dataTxId);

        final fileKey =
            await _driveDao.getFileKey(driveId, fileId, profile.cipherKey);

        dataBytes = await decryptTransactionData(dataTx, dataRes.data, fileKey);
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
    _dioClient.close(force: true);
    emit(FileDownloadAborted());
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(FileDownloadFailure());
    super.onError(error, stackTrace);

    print('Failed to download personal file: $error $stackTrace');
  }
}
