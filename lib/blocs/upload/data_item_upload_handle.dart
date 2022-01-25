import 'dart:convert';

import 'package:ardrive/blocs/upload/upload_handle.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/bundles/fake_tags.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:file_selector/file_selector.dart';
import 'package:moor/moor.dart';
import 'package:package_info_plus/package_info_plus.dart';

class DataItemUploadHandle implements UploadHandle, DataItemHandle {
  final FileEntity entity;
  final XFile file;
  final String path;
  final SecretKey? driveKey;
  final SecretKey? fileKey;
  final String revisionAction;

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

  DataItemUploadHandle({
    required this.entity,
    required this.path,
    required this.file,
    required this.revisionAction,
    required this.arweave,
    required this.wallet,
    this.driveKey,
    this.fileKey,
  });

  Future<void> writeEntityToDatabase({
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
    final packageInfo = await PackageInfo.fromPlatform();
    final fileData = await file.readAsBytes();
    dataTx = isPrivate
        ? await createEncryptedDataItem(fileData, fileKey!)
        : DataItem.withBlobData(data: fileData);
    dataTx.setOwner(await wallet.getOwner());

    dataTx.addApplicationTags(version: packageInfo.version);

    // Don't include the file's Content-Type tag if it is meant to be private.
    if (!isPrivate) {
      dataTx.addTag(
        EntityTag.contentType,
        entity.dataContentType!,
      );
    }

    await dataTx.sign(wallet);

    entity.dataTxId = dataTx.id;
    entityTx = await arweave.prepareEntityDataItem(entity, wallet, fileKey);
    await entityTx.sign(wallet);
    entity.txId = entityTx.id;

    return [entityTx, dataTx];
  }

  Future<int> _estimateEntityDataItemSize() async {
    final fakeTags = createFakeEntityTags(entity);
    if (isPrivate) {
      fakeTags.addAll(fakePrivateTags);
    } else {
      fakeTags.add(Tag(
        EntityTag.contentType,
        entity.dataContentType!,
      ));
    }
    fakeTags.addAll(fakeApplicationTags);
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

  Future<int> _estimatedataTxSize() async {
    final fakeTags = <Tag>[];
    if (isPrivate) {
      fakeTags.addAll(fakePrivateTags);
    } else {
      fakeTags.add(Tag(
        EntityTag.contentType,
        entity.dataContentType!,
      ));
    }
    fakeTags.addAll(fakeApplicationTags);
    return estimateDataItemSize(
      fileDataSize: size,
      tags: fakeTags,
      nonce: [],
    );
  }

  Future<int> estimateDataItemSizes() async {
    return await _estimatedataTxSize() + await _estimateEntityDataItemSize();
  }

  @override
  Future<List<DataItem>> createDataItemsFromFileHandle() async {
    final dataItems = await prepareAndSignDataItems();
    // Remove file data references
    return dataItems;
  }
}
