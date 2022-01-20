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

final bundleSizeLimit = 503316480;

class FileUploadHandle implements UploadHandle, DataItemHandle {
  final FileEntity entity;
  final XFile file;
  final String path;
  final bool isPrivate;
  final SecretKey? driveKey;
  final SecretKey? fileKey;

  Future<bool> isWithInBundleLimits() async {
    return await file.length() < bundleSizeLimit;
  }

  /// The size of the file before it was encoded/encrypted for upload.
  @override
  int get size => entity.size!;

  /// The size of the file that has been uploaded, not accounting for the file encoding/encryption overhead.
  @override
  int get uploadedSize => (size * uploadProgress).round();

  @override
  double uploadProgress = 0;

  TransactionBase? entityTx;
  TransactionBase? dataTx;

  ArweaveService arweave;
  DriveDao driveDao;
  Wallet wallet;

  String _revisionAction = RevisionAction.create;

  FileUploadHandle({
    required this.entity,
    required this.path,
    required this.file,
    required this.isPrivate,
    required this.arweave,
    required this.driveDao,
    required this.wallet,
    this.entityTx,
    this.dataTx,
    this.driveKey,
    this.fileKey,
  });

  void setRevisionAction(String action) => _revisionAction = action;

  Future<void> writeEntityToDatabase() async {
    if (entityTx?.id != null) {
      entity.txId = entityTx!.id;
    }

    await driveDao.writeFileEntity(entity, path);
    //  For V2 insert revision here, otherwise for bundles
    //  insert revision only after updating bundleTxId
    if (!await isWithInBundleLimits()) {
      await driveDao.insertFileRevision(
        entity.toRevisionCompanion(performedAction: _revisionAction),
      );
    }

    assert(entity.dataTxId == dataTx!.id);
  }

  Future<void> updateBundledInTxId({required String bundledInTxId}) async {
    entity.bundledIn = bundledInTxId;
    await driveDao.writeFileEntity(entity, path);

    await driveDao.insertFileRevision(
      entity.toRevisionCompanion(performedAction: _revisionAction),
    );
  }

  Future<void> prepareAndSignV2() async {
    final packageInfo = await PackageInfo.fromPlatform();

    final fileData = await file.readAsBytes();
    dataTx = isPrivate
        ? await createEncryptedDataItem(fileData, fileKey!)
        : DataItem.withBlobData(data: fileData);
    dataTx!.setOwner(await wallet.getOwner());

    dataTx!.addApplicationTags(version: packageInfo.version);

    // Don't include the file's Content-Type tag if it is meant to be private.
    if (!isPrivate) {
      dataTx!.addTag(
        EntityTag.contentType,
        entity.dataContentType!,
      );
    }

    await dataTx!.sign(wallet);

    entity.dataTxId = dataTx!.id;
    entityTx = await arweave.prepareEntityTx(entity, wallet, fileKey);
  }

  Future<List<DataItem>> prepareAndSignDataItems() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final fileData = await file.readAsBytes();
    dataTx = isPrivate
        ? await createEncryptedDataItem(fileData, fileKey!)
        : DataItem.withBlobData(data: fileData);
    final dataDataItem = dataTx as DataItem;
    dataDataItem.setOwner(await wallet.getOwner());

    dataDataItem.addApplicationTags(version: packageInfo.version);

    // Don't include the file's Content-Type tag if it is meant to be private.
    if (!isPrivate) {
      dataDataItem.addTag(
        EntityTag.contentType,
        entity.dataContentType!,
      );
    }

    await dataDataItem.sign(wallet);

    entity.dataTxId = dataDataItem.id;
    entityTx = await arweave.prepareEntityDataItem(entity, wallet, fileKey);
    final entityDataItem = entityTx as DataItem;

    await entityDataItem.sign(wallet);
    await dataDataItem.sign(wallet);
    return [entityDataItem, dataDataItem];
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

  Future<int> _estimateDataDataItemSize() async {
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
    return await _estimateDataDataItemSize() +
        await _estimateEntityDataItemSize();
  }

  BigInt estimateV2UploadCost() {
    return arweave.calculateARPriceForByteSize(byteSize: entity.size!) +
        arweave.calculateARPriceForByteSize(byteSize: getEntityJSONSize());
  }

  /// Uploads the file, emitting an event whenever the progress is updated.
  Stream<Null> upload(ArweaveService arweave) async* {
    if (entityTx != null) {
      await arweave.postTx(entityTx as Transaction);
    }

    await for (final upload
        in arweave.client.transactions.upload(dataTx as Transaction)) {
      uploadProgress = upload.progress;
      yield null;
    }
  }

  @override
  Future<List<DataItem>> createDataItemsFromFileHandle() async {
    final dataItems = await prepareAndSignDataItems();
    await writeEntityToDatabase();
    // Remove file data references
    dataTx = null;
    return dataItems;
  }
}
