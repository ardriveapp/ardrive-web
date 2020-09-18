import 'dart:convert';
import 'dart:typed_data';

import 'package:artemis/artemis.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:drive/repositories/entities/entity.dart';
import 'package:mime/mime.dart';
import 'package:pointycastle/export.dart';

import '../../services/services.dart';
import '../entities/entities.dart';
import 'graphql/graphql_api.dart';
import 'utils.dart';

class ArweaveDao {
  final ArtemisClient _gql = ArtemisClient('https://arweave.dev/graphql');
  final Arweave _arweave;

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
    final entityTxs = driveEntityHistoryQuery.data.transactions.edges
        .map((e) => e.node)
        .toList();
    final rawEntityData = await Future.wait(
        entityTxs.map((e) => _arweave.transactions.getData(e.id)));

    final blockHistory = <BlockEntities>[];
    for (var i = 0; i < entityTxs.length; i++) {
      final transaction = entityTxs[i];

      if (blockHistory.isEmpty ||
          transaction.block.height != blockHistory.last.blockHeight) {
        blockHistory.add(BlockEntities(transaction.block.height));
      }

      try {
        final entityType = transaction.getTag(EntityTag.entityType);
        final entityData =
            await _decodeEntityData(entityTxs[i], rawEntityData[i]);

        Entity entity;
        if (entityType == EntityType.drive) {
          entity = DriveEntity.fromTransaction(transaction, entityData);
        } else if (entityType == EntityType.folder) {
          entity = FolderEntity.fromTransaction(transaction, entityData);
        } else if (entityType == EntityType.file) {
          entity = FileEntity.fromTransaction(transaction, entityData);
        }

        if (blockHistory.isEmpty ||
            transaction.block.height != blockHistory.last.blockHeight) {
          blockHistory.add(BlockEntities(transaction.block.height));
        }

        blockHistory.last.entities.add(entity);

        // If there are errors in parsing the entity, ignore it.
        // ignore: empty_catches
      } catch (err) {
        rethrow;
      }
    }

    // Sort the entities in each block by ascending commit time.
    for (final block in blockHistory) {
      block.entities.sort((e1, e2) => e1.commitTime.compareTo(e2.commitTime));
    }

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

    final driveTx = queryEdges[0].node;
    final driveEntityData = await _decodeEntityData(
        driveTx, await _arweave.transactions.getData(driveTx.id));

    return DriveEntity.fromTransaction(driveTx, driveEntityData);
  }

  Future<Transaction> prepareEntityTx(Entity entity, Wallet wallet) async {
    final tx = await _arweave.transactions.prepare(
      entity.asTransaction(),
      wallet,
    );

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
      EntityTag.contentType,
      lookupMimeType(fileEntity.name),
    );

    await fileDataTx.sign(wallet);

    fileEntity.dataTxId = fileDataTx.id;

    final fileEntityTx = await prepareEntityTx(fileEntity, wallet);

    return UploadTransactions(fileEntityTx, fileDataTx);
  }

  Future<void> postTx(Transaction transaction) =>
      _arweave.transactions.post(transaction);

  Future<void> batchPostTxs(List<Transaction> transactions) =>
      Future.wait(transactions.map((tx) => _arweave.transactions.post(tx)));

  Future<Map<String, dynamic>> _decodeEntityData(
      TransactionCommonMixin transaction, String data,
      [KeyParameter driveKey]) async {
    final entityType = transaction.tags
        .firstWhere((t) => t.name == EntityTag.entityType)
        .value;

    Uint8List entityData;

    if (driveKey != null) {
      if (entityType == EntityType.drive) {
        entityData = await decryptDriveEntityData(
            transaction, utils.decodeBase64ToBytes(data), driveKey);
      } else if (entityType == EntityType.folder) {
        entityData = await decryptFolderEntityData(
            transaction, utils.decodeBase64ToBytes(data), driveKey);
      } else if (entityType == EntityType.file) {
        entityData = await decryptFileEntityData(
            transaction, utils.decodeBase64ToBytes(data), driveKey);
      }
    } else {
      entityData = utils.decodeBase64ToBytes(data);
    }

    return json.decode(utf8.decode(entityData));
  }
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
