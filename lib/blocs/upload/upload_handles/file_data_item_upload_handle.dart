import 'dart:convert';

import 'package:ardrive/blocs/upload/models/upload_file.dart';
import 'package:ardrive/blocs/upload/upload_handles/upload_handle.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/bundles/fake_tags.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';

// Number of data items returned by this handle
const fileDataItemEntityCount = 2;

class FileDataItemUploadHandle implements UploadHandle, DataItemHandle {
  final FileEntity entity;
  final UploadFile file;
  final String path;
  final SecretKey? driveKey;
  final SecretKey? fileKey;
  final String revisionAction;
  final String _platform;
  final String _version;

  /// The size of the file before it was encoded/encrypted for upload.
  @override
  int get size => entity.size!;

  /// The size of the file that has been uploaded, not accounting for the file encoding/encryption overhead.
  @override
  int get uploadedSize => (size * uploadProgress).round();

  bool get isPrivate => driveKey != null && fileKey != null;

  @override
  double uploadProgress = 0;

  late DataItem entityTx;
  late DataItem dataTx;

  ArweaveService arweave;
  Wallet wallet;

  FileDataItemUploadHandle({
    required this.entity,
    required this.path,
    required this.file,
    required this.revisionAction,
    required this.arweave,
    required this.wallet,
    this.driveKey,
    this.fileKey,
    required String platform,
    required String version,
  })  : _platform = platform,
        _version = version;

  Future<void> writeFileEntityToDatabase({
    required String bundledInTxId,
    required DriveDao driveDao,
  }) async {
    entity.bundledIn = bundledInTxId;
    await driveDao.transaction(() async {
      await driveDao.writeFileEntity(entity, path);
      await driveDao.insertFileRevision(
        entity.toRevisionCompanion(performedAction: revisionAction),
      );
    });
  }

  Future<List<DataItem>> prepareAndSignDataItems() async {
    final fileData = await file.ioFile.readAsBytes();

    dataTx = isPrivate
        ? await createEncryptedDataItem(fileData, fileKey!)
        : DataItem.withBlobData(data: fileData);
    dataTx.setOwner(await wallet.getOwner());

    dataTx.addApplicationTags(
      version: _version,
      platform: _platform,
    );

    // Don't include the file's Content-Type tag if it is meant to be private.
    if (!isPrivate) {
      dataTx.addTag(
        EntityTag.contentType,
        entity.dataContentType!,
      );
    }

    await dataTx.sign(wallet);

    entity.dataTxId = dataTx.id;
    entityTx = await arweave.prepareEntityDataItem(
      entity,
      wallet,
      key: fileKey,
    );
    await entityTx.sign(wallet);
    entity.txId = entityTx.id;

    return [entityTx, dataTx];
  }

  int _estimateEntityDataItemSize() {
    final fakeTags = createFakeEntityTags(entity);
    if (isPrivate) {
      fakeTags.addAll(fakePrivateTags);
    } else {
      fakeTags.add(Tag(
        EntityTag.contentType,
        entity.dataContentType!,
      ));
    }
    fakeTags.addAll(fakeApplicationTags(
      platform: _platform,
      version: _version,
    ));
    return estimateDataItemSize(
      fileDataSize: getEntityJSONSize(),
      tags: fakeTags,
      nonce: [],
    );
  }

  int getEntityJSONSize() {
    final entityFake = FileEntity(
      id: entity.id,
      dataContentType: entity.dataContentType,
      dataTxId: base64Encode(Uint8List(43)),
      driveId: entity.driveId,
      lastModifiedDate: entity.lastModifiedDate,
      name: entity.name,
      parentFolderId: entity.parentFolderId,
      size: entity.size,
    );
    return (utf8.encode(json.encode(entityFake)) as Uint8List).lengthInBytes;
  }

  int _estimatedataTxSize() {
    final fakeTags = <Tag>[];
    if (isPrivate) {
      fakeTags.addAll(fakePrivateTags);
    } else {
      fakeTags.add(Tag(
        EntityTag.contentType,
        entity.dataContentType!,
      ));
    }
    fakeTags.addAll(fakeApplicationTags(
      platform: _platform,
      version: _version,
    ));
    return estimateDataItemSize(
      fileDataSize: size,
      tags: fakeTags,
      nonce: [],
    );
  }

  int estimateDataItemSizes() {
    return _estimatedataTxSize() + _estimateEntityDataItemSize();
  }

  @override
  Future<List<DataItem>> getDataItems() async {
    final dataItems = await prepareAndSignDataItems();
    return dataItems;
  }

  // Returning a static count here to save memory and avoid any unneccessary data duplication
  @override
  int get dataItemCount => fileDataItemEntityCount;
}
