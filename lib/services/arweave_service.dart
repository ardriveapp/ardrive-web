import 'dart:typed_data';

import 'package:artemis/artemis.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:cryptography/cryptography.dart';
import 'package:drive/entities/entities.dart';
import 'package:mime/mime.dart';

import 'crypto/crypto.dart';

class ArweaveService {
  final ArtemisClient _gql = ArtemisClient('https://arweave.dev/graphql');
  final Arweave _arweave;

  ArweaveService(this._arweave);

  /// Get the entity history for a particular drive starting from the oldest block height.
  Future<DriveEntityHistory> getDriveEntityHistory(
    String driveId,
    int oldestBlockHeight, [
    SecretKey driveKey,
  ]) async {
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
            entityTxs.map((e) => _arweave.api.get('tx/${e.id}/data'))))
        .map((r) => utils.decodeBase64ToBytes(r.body))
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
          entity = await DriveEntity.fromTransaction(
              transaction, rawEntityData[i], driveKey);
        } else if (entityType == EntityType.folder) {
          entity = await FolderEntity.fromTransaction(
              transaction, rawEntityData[i], driveKey);
        } else if (entityType == EntityType.file) {
          entity = await FileEntity.fromTransaction(
              transaction, rawEntityData[i], driveKey);

          // TODO: Remove
          /*final file = entity as FileEntity;
          final fileKey = await deriveFileKey(driveKey, file.id);
          final dataTx = await _arweave.transactions.get(file.dataTxId);
          final cipherIv = utils.decodeBase64ToBytes(utils.decodeBase64ToString(
              dataTx.tags
                  .firstWhere((t) =>
                      t.name == utils.encodeStringToBase64(EntityTag.cipherIv))
                  .value));

          final dataRes = await _arweave.api.get('tx/${file.dataTxId}/data');
          final fileData = await aesGcm.decrypt(
            utils.decodeBase64ToBytes(dataRes.body),
            secretKey: SecretKey(fileKey.key),
            nonce: Nonce(cipherIv),
          );
          await File(file.name).writeAsBytes(fileData);*/
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

  Future<DriveEntity> getDriveEntity(String driveId,
      [SecretKey driveKey]) async {
    final initialDriveEntityQuery = await _gql.execute(
      InitialDriveEntityQuery(
          variables: InitialDriveEntityArguments(driveId: driveId)),
    );

    final queryEdges = initialDriveEntityQuery.data.transactions.edges;
    if (queryEdges.isEmpty) return null;

    final driveTx = queryEdges[0].node;

    return DriveEntity.fromTransaction(
      driveTx,
      utils.decodeBase64ToBytes(
          (await _arweave.api.get('tx/${driveTx.id}/data')).body),
      driveKey,
    );
  }

  Future<Transaction> prepareEntityTx(
    Entity entity,
    Wallet wallet, [
    SecretKey key,
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
    SecretKey driveKey,
  ]) async {
    final fileKey =
        driveKey == null ? null : await deriveFileKey(driveKey, fileEntity.id);

    final fileDataTx = await _arweave.transactions.prepare(
      fileKey == null
          ? Transaction.withBlobData(data: fileStream)
          : await createEncryptedTransaction(fileStream, fileKey),
      wallet,
    );

    if (fileKey == null) {
      fileDataTx.addTag(
        EntityTag.contentType,
        lookupMimeType(fileEntity.name),
      );
    }

    await fileDataTx.sign(wallet);

    fileEntity.dataTxId = fileDataTx.id;

    final fileEntityTx = await prepareEntityTx(fileEntity, wallet, fileKey);

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
