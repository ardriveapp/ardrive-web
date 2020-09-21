import 'dart:typed_data';

import 'package:artemis/artemis.dart';
import 'package:arweave/arweave.dart';
import 'package:mime/mime.dart';
import 'package:pointycastle/export.dart';

import '../entities/entities.dart';
import '../graphql/graphql.dart';

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
    final rawEntityData = (await Future.wait(
            entityTxs.map((e) => _arweave.api.get('tx/${e.id}/data.json'))))
        .map((r) => r.bodyBytes)
        .toList();

    final blockHistory = <BlockEntities>[];
    for (var i = 0; i < entityTxs.length; i++) {
      final transaction = entityTxs[i];

      if (blockHistory.isEmpty ||
          transaction.block.height != blockHistory.last.blockHeight) {
        blockHistory.add(BlockEntities(transaction.block.height));
      }

      try {
        final entityType = transaction.getTag(EntityTag.entityType);

        Entity entity;
        if (entityType == EntityType.drive) {
          entity =
              await DriveEntity.fromTransaction(transaction, rawEntityData[i]);
        } else if (entityType == EntityType.folder) {
          entity =
              await FolderEntity.fromTransaction(transaction, rawEntityData[i]);
        } else if (entityType == EntityType.file) {
          entity =
              await FileEntity.fromTransaction(transaction, rawEntityData[i]);
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

  Future<DriveEntity> getDriveEntity(String driveId, Wallet wallet) async {
    final initialDriveEntityQuery = await _gql.execute(
      InitialDriveEntityQuery(
          variables: InitialDriveEntityArguments(driveId: driveId)),
    );

    final queryEdges = initialDriveEntityQuery.data.transactions.edges;
    if (queryEdges.isEmpty) return null;

    final driveTx = queryEdges[0].node;

    return DriveEntity.fromTransaction(
        driveTx,
        (await _arweave.api.get('tx/${driveTx.id}/data.json')).bodyBytes,
        await deriveDriveKey(wallet, driveId, 'A?WgmN8gF%H9>A/~'));
  }

  Future<Transaction> prepareEntityTx(
    Entity entity,
    Wallet wallet, [
    KeyParameter key,
  ]) async {
    final tx = await _arweave.transactions.prepare(
      await entity.asTransaction(key),
      wallet,
    );

    await tx.sign(wallet);

    return tx;
  }

  Future<UploadTransactions> prepareFileUploadTxs(
    FileEntity fileEntity,
    Uint8List fileStream,
    Wallet wallet, [
    KeyParameter key,
  ]) async {
    final fileDataTx = await _arweave.transactions.prepare(
      key == null
          ? Transaction.withBlobData(data: fileStream)
          : await createEncryptedTransaction(fileStream, key),
      wallet,
    );

    fileDataTx.addTag(
      EntityTag.contentType,
      lookupMimeType(fileEntity.name),
    );

    await fileDataTx.sign(wallet);

    fileEntity.dataTxId = fileDataTx.id;

    final fileEntityTx = await prepareEntityTx(fileEntity, wallet, key);

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
