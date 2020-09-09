import 'dart:convert';
import 'dart:typed_data';

import 'package:artemis/artemis.dart';
import 'package:arweave/arweave.dart';
import 'package:drive/repositories/entities/entity.dart';
import 'package:mime/mime.dart';

import '../entities/entities.dart';
import 'graphql/graphql_api.dart';
import 'utils.dart';

class ArweaveDao {
  ArtemisClient _gql = ArtemisClient('https://arweave.dev/graphql');
  Arweave _arweave;

  ArweaveDao(this._arweave);

  /// Get the entity history for a particular drive starting from the oldest block height.
  Future<DriveEntityHistory> getDriveEntityHistory(
      String driveId, int oldestBlockHeight) async {
    final driveEntityHistoryQuery = await _gql.execute(
      DriveEntityHistoryQuery(
        variables: DriveEntityHistoryArguments(
          driveId: driveId,
          oldestBlockHeight: oldestBlockHeight,
        ),
      ),
    );
    final entityNodes = driveEntityHistoryQuery.data.transactions.edges
        .map((e) => e.node)
        .toList();
    final entityData = await Future.wait(
        entityNodes.map((e) => _arweave.transactions.getData(e.id, 'json')));

    final rawEntities = <RawEntity>[];
    for (var i = 0; i < entityNodes.length; i++) {
      // Entities can sometimes show up in queries even though they aren't mined yet so we'll have to check here.
      final entityJson =
          entityData[i] != null ? json.decode(entityData[i]) : null;

      // If the JSON is invalid, don't add it to the entities list.
      if (entityJson != null)
        rawEntities.add(
          RawEntity(
              txId: entityNodes[i].id,
              ownerAddress: entityNodes[i].owner.address,
              blockHeight: entityNodes[i].block.height,
              tags: entityNodes[i].tags,
              jsonData: entityJson),
        );
    }

    final blockHistory = <BlockEntities>[];
    for (final entity in rawEntities) {
      if (blockHistory.isEmpty ||
          entity.blockHeight != blockHistory.last.blockHeight)
        blockHistory.add(BlockEntities(entity.blockHeight));

      final entityType = entity.getTag(EntityTag.entityType);

      try {
        if (entityType == EntityType.drive) {
          final drive = DriveEntity.fromRawEntity(entity);
          blockHistory.last.entities.add(drive);
        } else if (entityType == EntityType.folder) {
          final folder = FolderEntity.fromRawEntity(entity);
          blockHistory.last.entities.add(folder);
        } else if (entityType == EntityType.file) {
          final file = FileEntity.fromRawEntity(entity);
          blockHistory.last.entities.add(file);
        }
        // If there are errors in parsing the entity, ignore it.
      } catch (err) {}
    }

    // Sort the entities in each block by ascending commit time.
    for (final block in blockHistory)
      block.entities.sort((e1, e2) => e1.commitTime.compareTo(e2.commitTime));

    return DriveEntityHistory(
        blockHistory.isNotEmpty
            ? blockHistory.last.blockHeight
            : oldestBlockHeight,
        blockHistory);
  }

  Future<DriveEntity> getDriveEntity(String driveId) async {
    final initialDriveEntityQuery = await _gql.execute(
      InitialDriveEntityQuery(
          variables: InitialDriveEntityArguments(driveId: driveId)),
    );

    final queryEdges = initialDriveEntityQuery.data.transactions.edges;
    if (queryEdges.isEmpty) return null;

    final driveNode = queryEdges[0].node;
    final driveEntityData =
        await _arweave.transactions.getData(driveNode.id, 'json');

    final entity = DriveEntity.fromRawEntity(
      RawEntity(
        txId: driveNode.id,
        ownerAddress: driveNode.owner.address,
        tags: driveNode.tags,
        jsonData: json.decode(driveEntityData),
      ),
    );

    return entity;
  }

  Future<Transaction> prepareDriveEntityTx(
      DriveEntity entity, Wallet wallet) async {
    assert(entity.id != null && entity.rootFolderId != null);

    final tx = await _arweave.transactions.prepare(
      Transaction.withStringData(data: json.encode(entity.toJson())),
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
    assert(entity.id != null && entity.driveId != null && entity.name != null);

    final tx = await _arweave.transactions.prepare(
      Transaction.withStringData(data: json.encode(entity.toJson())),
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

    final tx = await _arweave.transactions.prepare(
      Transaction.withStringData(data: json.encode(entity.toJson())),
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
    final fileDataTx = await _arweave.transactions.prepare(
      Transaction.withBlobData(data: fileStream),
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

  Future<void> postTx(Transaction transaction) =>
      _arweave.transactions.post(transaction);

  Future<void> batchPostTxs(List<Transaction> transactions) =>
      Future.wait(transactions.map((tx) => _arweave.transactions.post(tx)));
}

/// The entity history of a particular drive, chunked by block height.
class DriveEntityHistory {
  final int latestBlockHeight;

  /// A list of block entities, ordered by ascending block height.
  final List<BlockEntities> blockHistory;

  DriveEntityHistory(this.latestBlockHeight, this.blockHistory);
}

/// The entities present in a particular block.
class BlockEntities {
  final int blockHeight;

  /// A list of entities present in this block, ordered by ascending timestamp.
  List<Entity> entities = <Entity>[];

  BlockEntities(this.blockHeight);
}

class UploadTransactions {
  Transaction entityTx;
  Transaction dataTx;

  UploadTransactions(this.entityTx, this.dataTx);
}
