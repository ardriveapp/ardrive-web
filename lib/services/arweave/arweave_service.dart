import 'package:ardrive/entities/entities.dart';
import 'package:artemis/artemis.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';

import '../services.dart';

class ArweaveService {
  final Arweave client;

  final ArtemisClient _gql;

  ArweaveService(this.client)
      : _gql = ArtemisClient('${client.api.gatewayUrl.origin}/graphql');

  Future<TransactionCommonMixin> getTransactionDetails(String txId) async {
    final query = await _gql.execute(TransactionDetailsQuery(
        variables: TransactionDetailsArguments(txId: txId)));
    return query.data.transaction;
  }

  /// Gets the entity history for a particular drive starting from the specified block height.
  Future<DriveEntityHistory> getNewEntitiesForDrive(String driveId,
      {String after, SecretKey driveKey}) async {
    final driveEntityHistoryQuery = await _gql.execute(
      DriveEntityHistoryQuery(
        variables: DriveEntityHistoryArguments(
          driveId: driveId,
          after: after,
        ),
      ),
    );
    final queryEdges = driveEntityHistoryQuery.data.transactions.edges;
    final entityTxs = queryEdges.map((e) => e.node).toList();
    final rawEntityData =
        await Future.wait(entityTxs.map((e) => client.api.get(e.id)))
            .then((rs) => rs.map((r) => r.bodyBytes).toList());

    final blockHistory = <BlockEntities>[];
    for (var i = 0; i < entityTxs.length; i++) {
      final transaction = entityTxs[i];

      // If we encounter a transaction that has yet to be mined, we stop moving through history.
      // We can continue once the transaction is mined.
      if (transaction.block == null) {
        break;
      }

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
            transaction,
            rawEntityData[i],
            driveKey: driveKey,
          );
        }

        if (blockHistory.isEmpty ||
            transaction.block.height != blockHistory.last.blockHeight) {
          blockHistory.add(BlockEntities(transaction.block.height));
        }

        blockHistory.last.entities.add(entity);

        // If there are errors in parsing the entity, ignore it.
      } on EntityTransactionParseException catch (_) {}
    }

    // Sort the entities in each block by ascending commit time.
    for (final block in blockHistory) {
      block.entities.sort((e1, e2) => e1.commitTime.compareTo(e2.commitTime));
    }

    return DriveEntityHistory(
      queryEdges.isNotEmpty ? queryEdges.last.cursor : null,
      blockHistory,
    );
  }

  // Gets the unique drive entity transactions for a particular user.
  Future<List<TransactionCommonMixin>> getUniqueUserDriveEntityTxs(
      String userAddress) async {
    final userDriveEntitiesQuery = await _gql.execute(
      UserDriveEntitiesQuery(
          variables: UserDriveEntitiesArguments(owner: userAddress)),
    );

    return userDriveEntitiesQuery.data.transactions.edges
        .map((e) => e.node)
        .fold<Map<String, TransactionCommonMixin>>(
          {},
          (map, tx) {
            final driveId = tx.getTag('Drive-Id');
            if (!map.containsKey(driveId)) {
              map[driveId] = tx;
            }
            return map;
          },
        )
        .values
        .toList();
  }

  /// Gets the unique drive entities for a particular user.
  Future<Map<DriveEntity, SecretKey>> getUniqueUserDriveEntities(
    Wallet wallet,
    String password,
  ) async {
    final userDriveEntitiesQuery = await _gql.execute(
      UserDriveEntitiesQuery(
          variables: UserDriveEntitiesArguments(owner: wallet.address)),
    );

    final driveTxs = userDriveEntitiesQuery.data.transactions.edges
        .map((e) => e.node)
        .toList();

    final driveResponses =
        await Future.wait(driveTxs.map((e) => client.api.get(e.id)));

    final drivesById = <String, DriveEntity>{};
    final drivesWithKey = <DriveEntity, SecretKey>{};
    for (var i = 0; i < driveTxs.length; i++) {
      final driveTx = driveTxs[i];

      // Ignore drive entity transactions which we already have newer entities for.
      if (drivesById.containsKey(driveTx.getTag(EntityTag.driveId))) {
        continue;
      }

      final driveKey =
          driveTx.getTag(EntityTag.drivePrivacy) == DrivePrivacy.private
              ? await deriveDriveKey(
                  wallet,
                  driveTx.getTag(EntityTag.driveId),
                  password,
                )
              : null;

      try {
        final drive = await DriveEntity.fromTransaction(
          driveTx,
          driveResponses[i].bodyBytes,
          driveKey,
        );

        drivesById[drive.id] = drive;
        drivesWithKey[drive] = driveKey;

        // If there's an error parsing the drive entity, just ignore it.
      } on EntityTransactionParseException catch (_) {}
    }

    return drivesWithKey;
  }

  /// Gets the latest drive entity with the provided id.
  ///
  /// This function first checks for the owner of the first instance of the [DriveEntity]
  /// with the specified id and then queries for the latest instance of the [FileEntity]
  /// by that owner.
  ///
  /// Returns `null` if no valid drive is found or the provided `driveKey` is incorrect.
  Future<DriveEntity> getLatestDriveEntityWithId(
    String driveId, [
    SecretKey driveKey,
  ]) async {
    final firstOwnerQuery = await _gql.execute(FirstDriveEntityWithIdOwnerQuery(
        variables: FirstDriveEntityWithIdOwnerArguments(driveId: driveId)));

    if (firstOwnerQuery.data.transactions.edges.isEmpty) {
      return null;
    }

    final driveOwner =
        firstOwnerQuery.data.transactions.edges.first.node.owner.address;

    final latestDriveQuery = await _gql.execute(LatestDriveEntityWithIdQuery(
        variables: LatestDriveEntityWithIdArguments(
            driveId: driveId, owner: driveOwner)));

    final queryEdges = latestDriveQuery.data.transactions.edges;
    if (queryEdges.isEmpty) {
      return null;
    }

    final fileTx = queryEdges.first.node;
    final fileDataRes = await client.api.get(fileTx.id);

    try {
      return await DriveEntity.fromTransaction(
          fileTx, fileDataRes.bodyBytes, driveKey);
    } on EntityTransactionParseException catch (_) {
      return null;
    }
  }

  /// Gets the latest file entity with the provided id.
  ///
  /// This function first checks for the owner of the first instance of the [FileEntity]
  /// with the specified id and then queries for the latest instance of the [FileEntity]
  /// by that owner.
  ///
  /// Returns `null` if no valid file is found or the provided `fileKey` is incorrect.
  Future<FileEntity> getLatestFileEntityWithId(String fileId,
      [SecretKey fileKey]) async {
    final firstOwnerQuery = await _gql.execute(FirstFileEntityWithIdOwnerQuery(
        variables: FirstFileEntityWithIdOwnerArguments(fileId: fileId)));

    if (firstOwnerQuery.data.transactions.edges.isEmpty) {
      return null;
    }

    final fileOwner =
        firstOwnerQuery.data.transactions.edges.first.node.owner.address;

    final latestFileQuery = await _gql.execute(LatestFileEntityWithIdQuery(
        variables:
            LatestFileEntityWithIdArguments(fileId: fileId, owner: fileOwner)));

    final queryEdges = latestFileQuery.data.transactions.edges;
    if (queryEdges.isEmpty) {
      return null;
    }

    final fileTx = queryEdges.first.node;
    final fileDataRes = await client.api.get(fileTx.id);

    try {
      return await FileEntity.fromTransaction(
        fileTx,
        fileDataRes.bodyBytes,
        fileKey: fileKey,
      );
    } on EntityTransactionParseException catch (_) {
      return null;
    }
  }

  /// Returns the number of confirmations each specified transaction has as a map,
  /// keyed by the transactions' ids.
  ///
  /// When the number of confirmations is 0, the transaction has yet to be mined. When
  /// it is -1, the transaction could not be found.
  Future<Map<String, int>> getTransactionConfirmations(
      List<String> transactionIds) async {
    final transactionConfirmations = {
      for (final transactionId in transactionIds) transactionId: -1
    };

    // Chunk the transaction confirmation query to workaround the 10 item limit of the gateway API
    // and run it in parallel.
    const chunkSize = 10;

    final confirmationFutures = <Future<void>>[];

    for (var i = 0; i < transactionIds.length; i += chunkSize) {
      confirmationFutures.add(() async {
        final chunkEnd = (i + chunkSize < transactionIds.length)
            ? i + chunkSize
            : transactionIds.length;

        final query = await _gql.execute(
          TransactionStatusesQuery(
              variables: TransactionStatusesArguments(
                  transactionIds: transactionIds.sublist(i, chunkEnd))),
        );

        final currentBlockHeight = query.data.blocks.edges.first.node.height;

        for (final transaction
            in query.data.transactions.edges.map((e) => e.node)) {
          if (transaction.block == null) {
            transactionConfirmations[transaction.id] = 0;
            continue;
          }

          transactionConfirmations[transaction.id] =
              currentBlockHeight - transaction.block.height + 1;
        }
      }());
    }

    await Future.wait(confirmationFutures);

    return transactionConfirmations;
  }

  /// Creates and signs a [Transaction] representing the provided entity.
  ///
  /// Optionally provide a [SecretKey] to encrypt the entity data.
  Future<Transaction> prepareEntityTx(
    Entity entity,
    Wallet wallet, [
    SecretKey key,
  ]) async {
    final tx = await client.transactions.prepare(
      await entity.asTransaction(key),
      wallet,
    );

    await tx.sign(wallet);

    return tx;
  }

  /// Creates and signs a [DataItem] representing the provided entity.
  ///
  /// Optionally provide a [SecretKey] to encrypt the entity data.
  Future<DataItem> prepareEntityDataItem(
    Entity entity,
    Wallet wallet, [
    SecretKey key,
  ]) async {
    final item = await entity.asDataItem(key);
    item.setOwner(wallet.owner);

    await item.sign(wallet);

    return item;
  }

  /// Creates and signs a [Transaction] representing the provided [DataBundle].
  Future<Transaction> prepareDataBundleTx(
      DataBundle bundle, Wallet wallet) async {
    final bundleTx = await client.transactions.prepare(
      Transaction.withDataBundle(bundle: bundle)..addApplicationTags(),
      wallet,
    );

    await bundleTx.sign(wallet);

    return bundleTx;
  }

  Future<void> postTx(Transaction transaction) =>
      client.transactions.post(transaction);
}

/// The entity history of a particular drive, chunked by block height.
class DriveEntityHistory {
  /// A cursor for continuing through this drive's history.
  final String cursor;

  /// A list of block entities, ordered by ascending block height.
  final List<BlockEntities> blockHistory;

  DriveEntityHistory(this.cursor, this.blockHistory);
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
