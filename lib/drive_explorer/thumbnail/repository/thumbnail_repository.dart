import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/download/ardrive_downloader.dart';
import 'package:ardrive/drive_explorer/thumbnail/thumbnail.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' as drift;

class ThumbnailRepository {
  final ArweaveService _arweaveService;
  final ArDriveDownloader _arDriveDownloader;
  final DriveDao _driveDao;
  final ArDriveAuth _arDriveAuth;
  final ArDriveUploader _arDriveUploader;
  final TurboUploadService _turboUploadService;

  ThumbnailRepository({
    required ArweaveService arweaveService,
    required ArDriveDownloader arDriveDownloader,
    required DriveDao driveDao,
    required ArDriveAuth arDriveAuth,
    required ArDriveUploader arDriveUploader,
    required TurboUploadService turboUploadService,
  })  : _arDriveUploader = arDriveUploader,
        _driveDao = driveDao,
        _arDriveDownloader = arDriveDownloader,
        _arweaveService = arweaveService,
        _turboUploadService = turboUploadService,
        _arDriveAuth = arDriveAuth;

  Future<ThumbnailData> getThumbnail({
    FileDataTableItem? fileDataTableItem,
  }) async {
    final drive = await _driveDao
        .driveById(driveId: fileDataTableItem!.driveId)
        .getSingle();

    if (drive.isPrivate) {
      return ThumbnailData(
          data: await _getThumbnailData(fileDataTableItem: fileDataTableItem),
          url: null);
    }

    final urlString =
        '${_arweaveService.client.api.gatewayUrl.origin}/raw/${fileDataTableItem.thumbnail?.variants.first.txId}';

    return ThumbnailData(data: null, url: urlString);
  }

  Future<Uint8List> _getThumbnailData({
    required FileDataTableItem fileDataTableItem,
  }) async {
    final dataTx = await _arweaveService.getTransactionDetails(
      fileDataTableItem.thumbnail!.variants.first.txId,
    );

    if (dataTx == null) {
      throw Exception('Data transaction not found');
    }

    final driveKey = await _driveDao.getDriveKey(
        fileDataTableItem.driveId, _arDriveAuth.currentUser.cipherKey);

    return await _arDriveDownloader.downloadToMemory(
      dataTx: dataTx,
      fileSize: fileDataTableItem.thumbnail!.variants.first.size,
      fileName: fileDataTableItem.name,
      lastModifiedDate: fileDataTableItem.lastModifiedDate,
      contentType: 'image/jpeg',
      isManifest: false,
      cipher: dataTx.getTag(EntityTag.cipher),
      cipherIvString: dataTx.getTag(EntityTag.cipherIv),
      fileKey: await _driveDao.getFileKey(fileDataTableItem.id, driveKey!),
    );
  }

  Future<void> uploadThumbnail({
    required String fileId,
  }) async {
    var fileEntry = await (_driveDao.select(_driveDao.fileEntries)
          ..where((tbl) => tbl.id.equals(fileId)))
        .getSingle();
    // get image
    final dataTx =
        await _arweaveService.getTransactionDetails(fileEntry.dataTxId);

    SecretKey? fileKey;

    final drive =
        await _driveDao.driveById(driveId: fileEntry.driveId).getSingle();

    if (drive.isPrivate) {
      final driveKey = await _driveDao.getDriveKey(
        drive.id,
        _arDriveAuth.currentUser.cipherKey,
      );

      fileKey = await ArDriveCrypto().deriveFileKey(
        driveKey!,
        fileEntry.id,
      );
    }

    final bytes = await _arDriveDownloader.downloadToMemory(
      dataTx: dataTx!,
      fileSize: fileEntry.size,
      fileName: fileEntry.name,
      lastModifiedDate: fileEntry.lastModifiedDate,
      contentType: fileEntry.dataContentType!,
      isManifest: false,
      fileKey: fileKey,
      cipher: dataTx.getTag(EntityTag.cipher),
      cipherIvString: dataTx.getTag(EntityTag.cipherIv),
    );

    final data = await generateThumbnail(bytes, ThumbnailSize.small);

    final thumbnailFile = await IOFileAdapter().fromData(
      data.thumbnail,
      name: 'thumbnail',
      lastModifiedDate: DateTime.now(),
    );

    final thumbnailMetadata = ThumbnailUploadMetadata(
      contentType: 'image/jpeg',
      height: data.height,
      width: data.width,
      size: data.thumbnail.length,
      relatesTo: fileEntry.dataTxId,
      name: data.name,
      originalFileId: fileEntry.id,
    );

    final controller = await _arDriveUploader.uploadThumbnail(
      thumbnailMetadata: thumbnailMetadata,
      file: thumbnailFile,
      type: UploadType.turbo,
      wallet: _arDriveAuth.currentUser.wallet,
      fileKey: fileKey,
    );

    Completer<void> completer = Completer();

    controller.onDone((tasks) async {
      logger.i('Thumbnail uploaded');

      await _driveDao.transaction(() async {
        final thumbnailTask = tasks.first as ThumbnailUploadTask;

        final thumbnailData = {
          'variants': [thumbnailTask.metadata.toJson()]
        };

        fileEntry = fileEntry.copyWith(
          lastUpdated: DateTime.now(),
          thumbnail: drift.Value(jsonEncode(thumbnailData)),
        );

        final fileEntity = fileEntry.asEntity();

        final fileDataItem = await _arweaveService.prepareEntityDataItem(
          fileEntity,
          _arDriveAuth.currentUser.wallet,
          key: fileKey,
        );

        await _turboUploadService.postDataItem(
          dataItem: fileDataItem,
          wallet: _arDriveAuth.currentUser.wallet,
        );
        fileEntity.txId = fileDataItem.id;

        await _driveDao.writeToFile(fileEntry);
        fileEntity.txId = fileDataItem.id;

        await _driveDao.insertFileRevision(fileEntity.toRevisionCompanion(
            performedAction: RevisionAction.createThumbnail));

        completer.complete();
      });
    });

    return completer.future;
  }
}
