part of 'file_download_cubit.dart';

/// [ProfileFileDownloadCubit] includes logic to allow a user to download files
/// that they have attached to their profile.
class ProfileFileDownloadCubit extends FileDownloadCubit {
  final DriveID driveId;

  final FileID fileId;
  final String fileName;
  final int fileSize;
  final String? dataContentType;
  final DateTime lastModified;

  final TxID revisionDataTxId;

  final ProfileCubit _profileCubit;
  final DriveDao _driveDao;
  final ArweaveService _arweave;

  ProfileFileDownloadCubit({
    required this.driveId,
    required this.fileId,
    required this.fileName,
    required this.fileSize,
    required this.dataContentType,
    required this.lastModified,
    required this.revisionDataTxId,
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

      emit(
        FileDownloadInProgress(fileName: fileName, totalByteCount: fileSize),
      );
      final dataRes = await http.get(
        Uri.parse(
          '${_arweave.client.api.gatewayUrl.origin}/$revisionDataTxId',
        ),
      );

      late Uint8List dataBytes;

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
          final dataTx = await _arweave.getTransactionDetails(revisionDataTxId);

          if (dataTx != null) {
            dataBytes = await decryptTransactionData(
              dataTx,
              dataRes.bodyBytes,
              fileKey,
            );
          }

          break;
        case DrivePrivacy.public:
          dataBytes = dataRes.bodyBytes;
          break;
        default:
      }

      emit(
        FileDownloadSuccess(
          bytes: dataBytes,
          fileName: fileName,
          mimeType: dataContentType ?? lookupMimeType(fileName),
          lastModified: lastModified,
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
