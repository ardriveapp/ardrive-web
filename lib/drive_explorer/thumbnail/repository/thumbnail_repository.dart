import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/core/crypto/file_keys.dart';
import 'package:ardrive/download/ardrive_downloader.dart';
import 'package:ardrive/drive_explorer/thumbnail/missing_thumbnails.dart';
import 'package:ardrive/drive_explorer/thumbnail/thumbnail.dart';
import 'package:ardrive/entities/file_entity.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/arweave/transaction_tag_batcher.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' as drift;

// TODO(@thiagocarvalhodev): implement unit tests
class ThumbnailRepository {
  final ArweaveService _arweaveService;
  final ArDriveDownloader _arDriveDownloader;
  final DriveDao _driveDao;
  final FileKeys _fileKeys;
  final ArDriveAuth _arDriveAuth;
  final ArDriveUploader _arDriveUploader;
  final TurboUploadService _turboUploadService;

  ThumbnailRepository({
    required ArweaveService arweaveService,
    required ArDriveDownloader arDriveDownloader,
    required DriveDao driveDao,
    required FileKeys fileKeys,
    required ArDriveAuth arDriveAuth,
    required ArDriveUploader arDriveUploader,
    required TurboUploadService turboUploadService,
    TransactionTagBatcher? tagBatcher,
  })  : _arDriveUploader = arDriveUploader,
        _driveDao = driveDao,
        _fileKeys = fileKeys,
        _arDriveDownloader = arDriveDownloader,
        _arweaveService = arweaveService,
        _turboUploadService = turboUploadService,
        _arDriveAuth = arDriveAuth,
        _tagBatcher = tagBatcher ??
            TransactionTagBatcher(
              fetch: arweaveService.getTagsForTransactions,
            );

  /// Files whose image gave no thumbnail beyond what they have, such as one
  /// too small for a large thumbnail. For this session, so Make thumbnails
  /// does not keep offering them.
  final Set<String> _nothingToAdd = {};

  /// Whether Make thumbnails found nothing more to make for [fileId].
  bool hasNothingToAdd(String fileId) => _nothingToAdd.contains(fileId);

  /// A file's thumbnail variants; none when its record is missing or does
  /// not parse, as Make thumbnails reads it too.
  static List<Variant> _variantsOf(String? json) {
    if (json == null || json == 'null') return const [];
    try {
      return Thumbnail.fromJson(jsonDecode(json)).variants;
    } catch (_) {
      return const [];
    }
  }

  /// Reads the cipher tags of many thumbnails with one query.
  final TransactionTagBatcher _tagBatcher;
  final Map<String, ThumbnailData> _cachedThumbnails = {};

  Future<ThumbnailData> getThumbnail({
    required FileDataTableItem fileDataTableItem,
  }) async {
    if (_cachedThumbnails[fileDataTableItem.dataTxId] != null) {
      return _cachedThumbnails[fileDataTableItem.dataTxId]!;
    }

    final drive = await _driveDao
        .driveById(driveId: fileDataTableItem.driveId)
        .getSingle();

    if (drive.isPrivate) {
      _cachedThumbnails[fileDataTableItem.dataTxId] = ThumbnailData(
        data: await _getThumbnailData(fileDataTableItem: fileDataTableItem),
        url: null,
      );

      return _cachedThumbnails[fileDataTableItem.dataTxId]!;
    }

    final urlString =
        '${_arweaveService.client.api.gatewayUrl.origin}/raw/${fileDataTableItem.thumbnail?.variants.first.txId}';

    _cachedThumbnails[fileDataTableItem.dataTxId] =
        ThumbnailData(data: null, url: urlString);

    return _cachedThumbnails[fileDataTableItem.dataTxId]!;
  }

  Future<Uint8List> _getThumbnailData({
    required FileDataTableItem fileDataTableItem,
  }) {
    final variant = fileDataTableItem.thumbnail!.variants.first;
    return fetchPrivateVariantBytes(
      fileId: fileDataTableItem.id,
      driveId: fileDataTableItem.driveId,
      txId: variant.txId,
      size: variant.size,
      fileName: fileDataTableItem.name,
      lastModifiedDate: fileDataTableItem.lastModifiedDate,
    );
  }

  /// Starts reading the cipher tags of these private thumbnail variants in
  /// one batched query, so the downloads that follow find them ready. Does not
  /// wait and never throws: a failure here is met again, and reported, by the
  /// download itself.
  void prefetchPrivateVariantTags(Iterable<String> txIds) {
    for (final txId in txIds) {
      _tagBatcher.tagsFor(txId).ignore();
    }
  }

  /// Downloads and decrypts one thumbnail variant of a private file. Thumbnails
  /// are always for private files - need cipher/IV from the variant's tx. Used
  /// by [getThumbnail] and by the gallery image loader.
  Future<Uint8List> fetchPrivateVariantBytes({
    required String fileId,
    required String driveId,
    required String txId,
    required int size,
    required String fileName,
    required DateTime lastModifiedDate,
  }) async {
    // One batched query for every thumbnail asked for together. Throws
    // TransactionNotFoundException when the gateway has no such transaction.
    final tags = await _tagBatcher.tagsFor(txId);

    // A visitor has no profile, so their drive key is in the memory vault,
    // which is where download and preview already look; a private page's
    // visitor has only the page's file keys.
    final fileKey = await _fileKeys.keyFor(
      driveId: driveId,
      fileId: fileId,
      cipherKey: _cipherKeyOrNull(),
    );
    if (fileKey == null) {
      throw StateError('No key for the thumbnail of $fileId');
    }

    return await _arDriveDownloader.downloadToMemory(
      txId: txId,
      fileSize: size,
      fileName: fileName,
      lastModifiedDate: lastModifiedDate,
      contentType: 'image/jpeg',
      isManifest: false,
      cipher: tags[EntityTag.cipher],
      cipherIvString: tags[EntityTag.cipherIv],
      fileKey: fileKey,
    );
  }

  /// The signed-in profile's key, or null for a visitor.
  SecretKey? _cipherKeyOrNull() {
    try {
      return _arDriveAuth.currentUser.cipherKey;
    } on AuthenticationUserIsNotLoggedInException {
      return null;
    }
  }

  /// Makes the thumbnails the file lacks and records them beside the ones it
  /// has, small first. Answers whether anything was added: nothing is, and
  /// nothing is downloaded, when the file lacks nothing.
  Future<bool> uploadThumbnail({
    required String fileId,
  }) async {
    var fileEntry = await (_driveDao.select(_driveDao.fileEntries)
          ..where((tbl) => tbl.id.equals(fileId)))
        .getSingle();

    final existing = _variantsOf(fileEntry.thumbnail);
    final missing = missingThumbnailsOf(
      contentType: fileEntry.dataContentType,
      size: fileEntry.size,
      variants: existing,
    );
    // Asked for by name on a file thumbnails are not made for: as before,
    // make them, which is what Create thumbnail on one file has always done.
    final wantsAll = existing.isEmpty;
    if (missing == MissingThumbnails.none && !wantsAll) return false;

    SecretKey? fileKey;
    String? cipher;
    String? cipherIv;

    final drive =
        await _driveDao.driveById(driveId: fileEntry.driveId).getSingle();

    if (drive.isPrivate) {
      logger.d('Drive is private. Getting drive key');
      fileKey = await _fileKeys.keyFor(
        driveId: drive.id,
        fileId: fileEntry.id,
        cipherKey: _arDriveAuth.currentUser.cipherKey,
      );
      if (fileKey == null) {
        throw StateError('No key for ${fileEntry.id}');
      }

      // Private files need cipher/IV tags from the data transaction
      final dataTx =
          await _arweaveService.getTransactionDetails(fileEntry.dataTxId);
      if (dataTx == null) {
        throw Exception('Data transaction not found for ${fileEntry.dataTxId}');
      }
      cipher = dataTx.getTag(EntityTag.cipher);
      cipherIv = dataTx.getTag(EntityTag.cipherIv);
    }

    logger.d('Downloading file to memory');

    final bytes = await _arDriveDownloader.downloadToMemory(
      txId: fileEntry.dataTxId,
      fileSize: fileEntry.size,
      fileName: fileEntry.name,
      lastModifiedDate: fileEntry.lastModifiedDate,
      contentType: fileEntry.dataContentType!,
      isManifest: false,
      fileKey: fileKey,
      cipher: cipher,
      cipherIvString: cipherIv,
    );

    logger.d('Generating thumbnails');

    final generated = [
      for (final result in await generateThumbnails(bytes))
        // A file that has thumbnails keeps them; only a large one is added.
        if (wantsAll || result.name == ThumbnailSize.large.name) result,
    ];
    if (generated.isEmpty) {
      // Too small an image for a large one: not offered again this session.
      _nothingToAdd.add(fileId);
      return false;
    }

    // Small first, as older clients read the first variant.
    final uploaded = <ThumbnailUploadMetadata>[];
    // A payment refusal after the first landed: what landed is recorded,
    // then the refusal is reported, so a batch stops and says why.
    var refusedAfterFirst = false;
    for (final data in generated) {
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

      logger.d('Uploading thumbnail ${data.name}');
      try {
        uploaded.add(await _uploadOneThumbnail(
          metadata: thumbnailMetadata,
          file: thumbnailFile,
          fileKey: fileKey,
        ));
      } catch (e) {
        // Without the first one there is nothing to record; without the
        // large one the small one still serves every client.
        if (uploaded.isEmpty) rethrow;
        logger.w('Large thumbnail upload failed; keeping the small one: $e');
        if (isTurboPaymentError(e)) refusedAfterFirst = true;
      }
    }

    await _driveDao.transaction(() async {
      final thumbnailData = {
        'variants': [
          for (final variant in existing) variant.toJson(),
          for (final variant in uploaded) variant.toJson(),
        ]
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

      await _driveDao.insertFileRevision(fileEntity.toRevisionCompanion(
          performedAction: RevisionAction.createThumbnail));
    });
    if (refusedAfterFirst) throw ThumbnailsPartlyRefused();
    return true;
  }

  /// Uploads one thumbnail and answers its metadata, with its transaction id,
  /// once it is up.
  Future<ThumbnailUploadMetadata> _uploadOneThumbnail({
    required ThumbnailUploadMetadata metadata,
    required IOFile file,
    required SecretKey? fileKey,
  }) async {
    final controller = await _arDriveUploader.uploadThumbnail(
      thumbnailMetadata: metadata,
      file: file,
      type: UploadType.turbo,
      wallet: _arDriveAuth.currentUser.wallet,
      fileKey: fileKey,
    );

    final completer = Completer<ThumbnailUploadMetadata>();

    controller.onError((tasks) {
      logger.e('Error uploading thumbnail on upload controller', tasks,
          StackTrace.current);
      // The controller reports failures as a task list and does NOT call
      // onDone, so the completer must be errored here or the awaiting bloc
      // hangs forever. Surface payment rejections as the typed exception so
      // the bloc classifies them.
      if (!completer.isCompleted) {
        completer.completeError(
          anyTaskIsTurboPaymentError(tasks.map((t) => t.error))
              ? TurboPaymentRequiredException()
              : Exception('Thumbnail upload failed'),
        );
      }
    });

    controller.onDone((tasks) {
      logger.i('Thumbnail uploaded');
      if (!completer.isCompleted) {
        completer.complete((tasks.first as ThumbnailUploadTask).metadata);
      }
    });

    return completer.future;
  }
}

/// Some of a file's thumbnails were added and recorded, then Turbo refused
/// the rest for payment. A payment error, so callers that stop on one do;
/// one that counts what was made counts this file too.
class ThumbnailsPartlyRefused extends TurboPaymentRequiredException {
  ThumbnailsPartlyRefused();
}
