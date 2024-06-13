import 'dart:typed_data';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/download/ardrive_downloader.dart';
import 'package:ardrive/drive_explorer/thumbnail/thumbnail.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive_utils/ardrive_utils.dart';

class ThumbnailRepository {
  final ArweaveService _arweaveService;
  final ArDriveDownloader _arDriveDownloader;
  final DriveDao _driveDao;
  final ArDriveAuth _arDriveAuth;

  ThumbnailRepository({
    required ArweaveService arweaveService,
    required ArDriveDownloader arDriveDownloader,
    required DriveDao driveDao,
    required ArDriveAuth arDriveAuth,
  })  : _driveDao = driveDao,
        _arDriveDownloader = arDriveDownloader,
        _arweaveService = arweaveService,
        _arDriveAuth = arDriveAuth;

  Future<Thumbnail> getThumbnail({
    FileDataTableItem? fileDataTableItem,
    bool returnData = false,
  }) async {
    final drive = await _driveDao
        .driveById(driveId: fileDataTableItem!.driveId)
        .getSingle();

    if (drive.isPrivate) {
      return Thumbnail(
          data: await _getThumbnailData(fileDataTableItem: fileDataTableItem),
          url: null);
    }

    final urlString =
        '${_arweaveService.client.api.gatewayUrl.origin}/raw/${fileDataTableItem.thumbnailUrl}';

    return Thumbnail(data: null, url: urlString);
  }

  Future<Uint8List> _getThumbnailData({
  FileDataTableItem? fileDataTableItem,
  }) async {
    final dataTx = await _arweaveService.getTransactionDetails(
      fileDataTableItem!.thumbnailUrl!,
    );

    if (dataTx == null) {
      throw Exception('Data transaction not found');
    }

    final driveKey = await _driveDao.getDriveKey(
        fileDataTableItem.driveId, _arDriveAuth.currentUser.cipherKey);

    return await _arDriveDownloader.downloadToMemory(
      dataTx: dataTx,
      fileSize: fileDataTableItem.size!,
      fileName: fileDataTableItem.name,
      lastModifiedDate: fileDataTableItem.lastModifiedDate,
      contentType: fileDataTableItem.contentType,
      isManifest: false,
      cipher: dataTx.getTag(EntityTag.cipher),
      cipherIvString: dataTx.getTag(EntityTag.cipherIv),
      fileKey: await _driveDao.getFileKey(fileDataTableItem.id, driveKey!),
    );
  }
}
