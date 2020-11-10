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
  Future<DriveEntityHistory> getNewEntitiesForDriveSinceBlock(
    String driveId,
    int startingBlockHeight, [
    SecretKey driveKey,
  ]) async {
    final driveEntityHistoryQuery = await _gql.execute(
      DriveEntityHistoryQuery(
        variables: DriveEntityHistoryArguments(
          driveId: driveId,
          startingBlockHeight: startingBlockHeight,
        ),
      ),
    );
    final entityTxs = driveEntityHistoryQuery.data.transactions.edges
        .map((e) => e.node)
        .toList();
    final rawEntityData =
        (await Future.wait(entityTxs.map((e) => client.api.get(e.id))))
            .map((r) => r.bodyBytes)
            .toList();

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
              transaction, rawEntityData[i], driveKey);
        }

        if (blockHistory.isEmpty ||
            transaction.block.height != blockHistory.last.blockHeight) {
          blockHistory.add(BlockEntities(transaction.block.height));
        }

        blockHistory.last.entities.add(entity);
      } catch (err) {
        // If there are errors in parsing the entity, ignore it.
        // TODO: Test graceful handling of invalid entities.
        if (err is! EntityTransactionParseException) {
          rethrow;
        }
      }
    }

    // Sort the entities in each block by ascending commit time.
    for (final block in blockHistory) {
      block.entities.sort((e1, e2) => e1.commitTime.compareTo(e2.commitTime));
    }

    return DriveEntityHistory(
      blockHistory.isNotEmpty
          ? blockHistory.last.blockHeight
          : startingBlockHeight,
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
      } catch (err) {
        // If there's an error parsing the drive entity, just ignore it.
        // TODO: Test graceful handling of invalid entities.
        if (err is! EntityTransactionParseException) {
          rethrow;
        }
      }
    }

    return drivesWithKey;
  }

  /// Tries to get the first drive entity instance with the provided drive id.
  /// Important for verifying the owner of a drive.
  ///
  /// Optionally provide a `driveKey` to load private drive entities.
  ///
  /// Returns `null` if no drive could be found.
  Future<DriveEntity> tryGetFirstDriveEntityWithId(
    String driveId, [
    SecretKey driveKey,
  ]) async {
    final initialDriveEntityQuery = await _gql.execute(
      InitialDriveEntityQuery(
          variables: InitialDriveEntityArguments(driveId: driveId)),
    );

    final queryEdges = initialDriveEntityQuery.data.transactions.edges;
    if (queryEdges.isEmpty) return null;

    final driveTx = queryEdges[0].node;
    final driveDataRes = await client.api.get(driveTx.id);

    return DriveEntity.fromTransaction(
      driveTx,
      driveDataRes.bodyBytes,
      driveKey,
    );
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
    final item = await entity.asDataItem();
    item.setOwner(wallet.owner);

    await item.sign(wallet);

    return item;
  }

  /// Creates and signs a [Transaction] representing the provided [DataBundle].
  Future<Transaction> prepareDataBundleTx(
      DataBundle bundle, Wallet wallet) async {
    final bundleTx = await client.transactions.prepare(
      Transaction.withDataBundle(bundle: bundle),
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
