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

  Future<Transaction> prepareDriveEntity(
      String driveId, String rootFolderId, Wallet wallet) async {
    final driveEntity = DriveEntity(rootFolderId);

    final driveEntityTx = await _arweave.createTransaction(
      Transaction(data: json.encode(driveEntity.toJson())),
      wallet,
    );

    driveEntityTx.addApplicationTags();
    driveEntityTx.addJsonContentTypeTag();
    driveEntityTx.addTag(EntityTag.entityType, 'drive');
    driveEntityTx.addTag(EntityTag.driveId, driveId);

    await driveEntityTx.sign(wallet);

    return driveEntityTx;
  }

  Future<Transaction> prepareFolderEntity(
    String folderId,
    String driveId,
    String parentFolderId,
    String name,
    Wallet wallet,
  ) async {
    final folderEntity = FolderEntity(name);

    final folderEntityTx = await _arweave.createTransaction(
      Transaction(data: json.encode(folderEntity.toJson())),
      wallet,
    );

    folderEntityTx.addApplicationTags();
    folderEntityTx.addJsonContentTypeTag();
    folderEntityTx.addTag(EntityTag.entityType, 'folder');
    folderEntityTx.addTag(EntityTag.driveId, driveId);
    folderEntityTx.addTag(EntityTag.folderId, folderId);

    if (parentFolderId != null)
      folderEntityTx.addTag(EntityTag.parentFolderId, parentFolderId);

    await folderEntityTx.sign(wallet);

    return folderEntityTx;
  }

  Future<Transaction> prepareFileEntity(
      String fileId,
      String driveId,
      String parentFolderId,
      String name,
      String dataTxId,
      int fileSize,
      Wallet wallet) async {
    final fileEntity = FileEntity(name, fileSize, dataTxId);

    final fileEntityTx = await _arweave.createTransaction(
      Transaction(data: json.encode(fileEntity.toJson())),
      wallet,
    );

    fileEntityTx.addApplicationTags();
    fileEntityTx.addJsonContentTypeTag();
    fileEntityTx.addTag(EntityTag.entityType, 'file');
    fileEntityTx.addTag(EntityTag.driveId, driveId);
    fileEntityTx.addTag(EntityTag.parentFolderId, parentFolderId);
    fileEntityTx.addTag(EntityTag.fileId, fileId);

    await fileEntityTx.sign(wallet);

    return fileEntityTx;
  }

  Future<UploadTransactions> prepareFileUpload(
    String fileId,
    String driveId,
    String parentFolderId,
    String name,
    int fileSize,
    Uint8List fileStream,
    Wallet wallet,
  ) async {
    final fileDataTx = await _arweave.createTransaction(
      Transaction(dataBytes: fileStream),
      wallet,
    );

    fileDataTx.addTag(
      'Content-Type',
      lookupMimeType(name),
    );

    await fileDataTx.sign(wallet);

    final fileEntityTx = await prepareFileEntity(
        fileId, driveId, parentFolderId, name, fileDataTx.id, fileSize, wallet);

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
