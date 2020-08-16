import 'dart:convert';
import 'dart:typed_data';

import 'package:artemis/artemis.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/src/utils.dart' as utils;
import 'package:http/http.dart';
import 'package:mime/mime.dart';

import '../entities/entities.dart';
import 'graphql/graphql_api.dart';
import 'utils.dart';

class ArweaveDao {
  ArtemisClient _gql = ArtemisClient('https://arweave.dev/graphql');
  Arweave _arweave;

  ArweaveDao(this._arweave);

  Future<UpdatedEntities> getUpdatedEntities(
      String address, int latestBlockNumber) async {
    final updatedEntitiesQuery = await _gql.execute(UpdatedEntitiesQuery(
        variables:
            UpdatedEntitiesArguments(minBlockNumber: latestBlockNumber)));
    final entityNodes = updatedEntitiesQuery.data.transactions.edges
        .map((e) => e.node)
        .toList();
    final entityData = (await Future.wait(
        entityNodes.map((e) => _arweave.transactions.getData(e.id)).toList()));

    final rawEntities = <RawEntity>[];
    for (var i = 0; i < entityNodes.length; i++) {
      // Entities can sometimes show up in queries even though they aren't mined yet so we'll have to check here.
      final entityJson = entityData[i] != null
          ? json.decode(utils.decodeBase64ToString(entityData[i]))
          : null;

      // If the JSON is invalid, don't add it to the entities list.
      if (entityJson != null)
        rawEntities
            .add(RawEntity(entityNodes[i].id, entityNodes[i].tags, entityJson));
    }

    final driveEntities = <String, DriveEntity>{};
    final folderEntitites = <String, FolderEntity>{};
    final fileEntities = <String, FileEntity>{};

    for (final entity in rawEntities) {
      final entityType = entity.getTag(EntityTag.entityType);

      if (entityType == EntityType.drive) {
        final drive = DriveEntity.fromRawEntity(entity);
        if (!driveEntities.containsKey(drive.id))
          driveEntities[drive.id] = drive;
      } else if (entityType == EntityType.folder) {
        final folder = FolderEntity.fromRawEntity(entity);
        if (!folderEntitites.containsKey(folder.id))
          folderEntitites[folder.id] = folder;
      } else if (entityType == EntityType.file) {
        final file = FileEntity.fromRawEntity(entity);
        if (!fileEntities.containsKey(file.id)) fileEntities[file.id] = file;
      }
    }

    return UpdatedEntities(
        latestBlockNumber, driveEntities, folderEntitites, fileEntities);
  }

  Future<DriveEntity> getDriveEntity(String driveId) async {
    final driveTxId = (await _arweave.transactions.arql({
      "op": "and",
      "expr1": {
        "op": "equals",
        "expr1": EntityTag.entityType,
        "expr2": "drive"
      },
      "expr2": {
        "op": "equals",
        "expr1": EntityTag.driveId,
        "expr2": driveId,
      },
    }))[0];
    final driveTx = await _arweave.transactions.get(driveTxId);

    final entity = DriveEntity.fromJson(
        json.decode(utils.decodeBase64ToString(driveTx.data)));
    entity.id = driveTx.id;

    return entity;
  }

  Future<Transaction> prepareDriveEntityTx(
      DriveEntity entity, Wallet wallet) async {
    assert(entity.id != null && entity.rootFolderId != null);

    final tx = await _arweave.createTransaction(
      Transaction(data: json.encode(entity.toJson())),
      wallet,
    );

    tx.addApplicationTags();
    tx.addJsonContentTypeTag();
    tx.addTag(EntityTag.entityType, 'drive');
    tx.addTag(EntityTag.driveId, entity.id);

    await tx.sign(wallet);

    return tx;
  }

  Future<Transaction> prepareFolderEntityTx(
    FolderEntity entity,
    Wallet wallet,
  ) async {
    assert(entity.id != null &&
        entity.driveId != null &&
        entity.parentFolderId != null &&
        entity.name != null);

    final tx = await _arweave.createTransaction(
      Transaction(data: json.encode(entity.toJson())),
      wallet,
    );

    tx.addApplicationTags();
    tx.addJsonContentTypeTag();
    tx.addTag(EntityTag.entityType, 'folder');
    tx.addTag(EntityTag.driveId, entity.driveId);
    tx.addTag(EntityTag.folderId, entity.id);

    if (entity.parentFolderId != null)
      tx.addTag(EntityTag.parentFolderId, entity.parentFolderId);

    await tx.sign(wallet);

    return tx;
  }

  Future<Transaction> prepareFileEntityTx(
      FileEntity entity, Wallet wallet) async {
    assert(entity.id != null &&
        entity.driveId != null &&
        entity.parentFolderId != null &&
        entity.name != null &&
        entity.size != null);

    final tx = await _arweave.createTransaction(
      Transaction(data: json.encode(entity.toJson())),
      wallet,
    );

    tx.addApplicationTags();
    tx.addJsonContentTypeTag();
    tx.addTag(EntityTag.entityType, 'file');
    tx.addTag(EntityTag.driveId, entity.driveId);
    tx.addTag(EntityTag.parentFolderId, entity.parentFolderId);
    tx.addTag(EntityTag.fileId, entity.id);

    await tx.sign(wallet);

    return tx;
  }

  Future<UploadTransactions> prepareFileUploadTxs(
    FileEntity fileEntity,
    Uint8List fileStream,
    Wallet wallet,
  ) async {
    final fileDataTx = await _arweave.createTransaction(
      Transaction(dataBytes: fileStream),
      wallet,
    );

    fileDataTx.addTag(
      'Content-Type',
      lookupMimeType(fileEntity.name),
    );

    await fileDataTx.sign(wallet);

    fileEntity.dataTxId = fileDataTx.id;

    final fileEntityTx = await prepareFileEntityTx(fileEntity, wallet);

    return UploadTransactions(fileEntityTx, fileDataTx);
  }

  Future<List<Response>> batchPostTxs(List<Transaction> transactions) =>
      Future.wait(transactions.map((tx) => _arweave.transactions.post(tx)));
}

class UpdatedEntities {
  final int latestBlockNumber;
  final Map<String, DriveEntity> drives;
  final Map<String, FolderEntity> folders;
  final Map<String, FileEntity> files;

  UpdatedEntities(
      this.latestBlockNumber, this.drives, this.folders, this.files);
}

class UploadTransactions {
  Transaction entityTx;
  Transaction dataTx;

  UploadTransactions(this.entityTx, this.dataTx);
}
