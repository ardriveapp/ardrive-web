import 'dart:async';
import 'dart:convert';

import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/graphql_retry.dart';
import 'package:artemis/artemis.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:moor/moor.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:retry/retry.dart';

const byteCountPerChunk = 262144; // 256 KiB

const kMaxNumberOfTransactionsPerPage = 100;

class ArweaveService {
  final Arweave client;

  final ArtemisClient _gql;

  ArweaveService(this.client)
      : _gql = ArtemisClient('${client.api.gatewayUrl.origin}/graphql') {
    _graphQLRetry = GraphQLRetry(_gql);
  }

  int bytesToChunks(int bytes) {
    return (bytes / byteCountPerChunk).ceil();
  }

  late GraphQLRetry _graphQLRetry;

  /// Returns the onchain balance of the specified address.
  Future<BigInt> getWalletBalance(String address) => client.api
      .get('wallet/$address/balance')
      .then((res) => BigInt.parse(res.body));

  Future<int> getCurrentBlockHeight() =>
      client.api.get('/').then((res) => json.decode(res.body)['height']);

  Future<BigInt> getPrice({required int byteSize}) {
    return client.api
        .get('/price/$byteSize')
        .then((res) => BigInt.parse(res.body));
  }

  Future<int> getMempoolSizeFromArweave() async {
    final response = await client.api.get('tx/pending');

    if (response.statusCode == 200) {
      return (json.decode(response.body) as List).length;
    }

    throw Exception('Error fetching mempool size');
  }

  /// Returns the pending transaction fees of the specified address that is not reflected by `getWalletBalance()`.
  Future<BigInt> getPendingTxFees(String address) async {
    final query = await _graphQLRetry.execute(PendingTxFeesQuery(
        variables: PendingTxFeesArguments(walletAddress: address)));

    return query.data!.transactions.edges
        .map((edge) => edge.node)
        .where((node) => node.block == null)
        .fold<BigInt>(
          BigInt.zero,
          (totalFees, node) => totalFees + BigInt.parse(node.fee.winston),
        );
  }

  Future<TransactionCommonMixin?> getTransactionDetails(String txId) async {
    final query = await _gql.execute(TransactionDetailsQuery(
        variables: TransactionDetailsArguments(txId: txId)));
    return query.data?.transaction;
  }

  Stream<List<DriveEntityHistory$Query$TransactionConnection$TransactionEdge>>
      getAllTransactionsFromDrive(
    String driveId, {
    int? lastBlockHeight,
  }) async* {
    String? cursor;

    while (true) {
      // Get a page of 100 transactions
      final driveEntityHistoryQuery = await _graphQLRetry.execute(
        DriveEntityHistoryQuery(
          variables: DriveEntityHistoryArguments(
            driveId: driveId,
            lastBlockHeight: lastBlockHeight,
            after: cursor,
          ),
        ),
      );

      yield driveEntityHistoryQuery.data!.transactions.edges;

      cursor = driveEntityHistoryQuery.data!.transactions.edges.isNotEmpty
          ? driveEntityHistoryQuery.data!.transactions.edges.last.cursor
          : null;

      if (!driveEntityHistoryQuery.data!.transactions.pageInfo.hasNextPage) {
        break;
      }
    }
  }

  /// Get the metadata of transactions
  ///
  /// mounts the `blockHistory`
  ///
  /// returns DriveEntityHistory object
  Future<DriveEntityHistory> createDriveEntityHistoryFromTransactions(
      List<DriveEntityHistory$Query$TransactionConnection$TransactionEdge>
          queryEdges,
      SecretKey? driveKey,
      String? owner,
      int lastBlockHeight) async {
    final entityTxs = <
        DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction>[];
    entityTxs.addAll(queryEdges.map((e) => e.node).toList());

    final responses = await Future.wait(
      entityTxs.map((e) async {
        return retry(
          () => client.api.getSandboxedTx(e.id),
          onRetry: (exception) {
            print(
              'Retrying for get ${e.id} metadata on exception ${exception.toString()}',
            );
          },
        );
      }),
    );

    final blockHistory = <BlockEntities>[];

    for (var i = 0; i < entityTxs.length; i++) {
      final transaction = entityTxs[i];
      // If we encounter a transaction that has yet to be mined, we stop moving through history.
      // We can continue once the transaction is mined.
      if (transaction.block == null) {
        // TODO: Revisit
        break;
      }

      if (blockHistory.isEmpty ||
          transaction.block!.height != blockHistory.last.blockHeight) {
        blockHistory.add(BlockEntities(transaction.block!.height));
      }

      try {
        final entityType = transaction.getTag(EntityTag.entityType);
        final entityResponse = responses[i];

        if (entityResponse.statusCode != 200) {
          throw EntityTransactionDataNetworkException(
            transactionId: transaction.id,
            statusCode: entityResponse.statusCode,
            reasonPhrase: entityResponse.reasonPhrase,
          );
        }

        final rawEntityData = entityResponse.bodyBytes;

        Entity? entity;
        if (entityType == EntityType.drive) {
          entity = await DriveEntity.fromTransaction(
              transaction, rawEntityData, driveKey);
        } else if (entityType == EntityType.folder) {
          entity = await FolderEntity.fromTransaction(
              transaction, rawEntityData, driveKey);
        } else if (entityType == EntityType.file) {
          entity = await FileEntity.fromTransaction(
            transaction,
            rawEntityData,
            driveKey: driveKey,
          );
        }
        //TODO: Revisit
        if (blockHistory.isEmpty ||
            transaction.block!.height != blockHistory.last.blockHeight) {
          blockHistory.add(BlockEntities(transaction.block!.height));
        }

        blockHistory.last.entities.add(entity);

        // If there are errors in parsing the entity, ignore it.
      } on EntityTransactionParseException catch (parseException) {
        print(
          'Failed to parse transaction '
          'with id ${parseException.transactionId}',
        );
      } on EntityTransactionDataNetworkException catch (fetchException) {
        print(
          'Failed to fetch entity data '
          'for transaction ${fetchException.transactionId}, '
          'with status ${fetchException.statusCode} '
          'and reason ${fetchException.reasonPhrase}',
        );
      }
    }

    // Sort the entities in each block by ascending commit time.
    for (final block in blockHistory) {
      block.entities.sort((e1, e2) => e1!.createdAt.compareTo(e2!.createdAt));
      //Remove entities with spoofed owners
      block.entities.removeWhere((e) => e!.ownerAddress != owner);
    }

    return DriveEntityHistory(
      queryEdges.isNotEmpty ? queryEdges.last.cursor : null,
      blockHistory.isNotEmpty ? blockHistory.last.blockHeight : lastBlockHeight,
      blockHistory,
    );
  }

  // Gets the unique drive entity transactions for a particular user.
  Future<List<TransactionCommonMixin>> getUniqueUserDriveEntityTxs(
      String userAddress) async {
    final userDriveEntitiesQuery = await _graphQLRetry.execute(
      UserDriveEntitiesQuery(
          variables: UserDriveEntitiesArguments(owner: userAddress)),
    );

    return userDriveEntitiesQuery.data!.transactions.edges
        .map((e) => e.node)
        .fold<Map<String?, TransactionCommonMixin>>(
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
  Future<Map<DriveEntity, SecretKey?>> getUniqueUserDriveEntities(
    Wallet wallet,
    String password,
  ) async {
    try {
      final userDriveEntitiesQuery = await _graphQLRetry.execute(
          UserDriveEntitiesQuery(
              variables: UserDriveEntitiesArguments(
                  owner: await wallet.getAddress())));

      final driveTxs = userDriveEntitiesQuery.data!.transactions.edges
          .map((e) => e.node)
          .toList();

      final driveResponses = await retry(
          () async => await Future.wait(
                driveTxs.map((e) => client.api.getSandboxedTx(e.id)),
              ), onRetry: (Exception err) {
        print(
            'Retrying for get unique user drive entities on Exception: ${err.toString()}');
      });

      final drivesById = <String?, DriveEntity>{};
      final drivesWithKey = <DriveEntity, SecretKey?>{};
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
                    driveTx.getTag(EntityTag.driveId)!,
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
        } on EntityTransactionParseException catch (parseException) {
          print(
            'Failed to parse transaction '
            'with id ${parseException.transactionId}',
          );
        }
      }
      return drivesWithKey;
    } catch (e, stacktrace) {
      print(
          'An error occurs getting the unique user drive entities. Exception: ${e.toString()} stacktrace: ${stacktrace.toString()}');
      rethrow;
    }
  }

  /// Gets the latest drive entity with the provided id.
  ///
  /// This function first checks for the owner of the first instance of the [DriveEntity]
  /// with the specified id and then queries for the latest instance of the [FileEntity]
  /// by that owner.
  ///
  /// Returns `null` if no valid drive is found or the provided `driveKey` is incorrect.
  Future<DriveEntity?> getLatestDriveEntityWithId(
    String driveId, [
    SecretKey? driveKey,
  ]) async {
    final firstOwnerQuery = await _gql.execute(FirstDriveEntityWithIdOwnerQuery(
        variables: FirstDriveEntityWithIdOwnerArguments(driveId: driveId)));

    if (firstOwnerQuery.data!.transactions.edges.isEmpty) {
      return null;
    }

    final driveOwner =
        firstOwnerQuery.data!.transactions.edges.first.node.owner.address;

    final latestDriveQuery = await _gql.execute(LatestDriveEntityWithIdQuery(
        variables: LatestDriveEntityWithIdArguments(
            driveId: driveId, owner: driveOwner)));

    final queryEdges = latestDriveQuery.data!.transactions.edges;
    if (queryEdges.isEmpty) {
      return null;
    }

    final fileTx = queryEdges.first.node;
    final fileDataRes = await client.api.getSandboxedTx(fileTx.id);

    try {
      return await DriveEntity.fromTransaction(
          fileTx, fileDataRes.bodyBytes, driveKey);
    } on EntityTransactionParseException catch (parseException) {
      print(
        'Failed to parse transaction '
        'with id ${parseException.transactionId}',
      );
      return null;
    }
  }

  /// Gets the drive privacy of the latest drive entity with the provided id.
  ///
  /// This function first checks for the owner of the first instance of the [DriveEntity]
  /// with the specified id and then queries for the latest instance of the [DriveEntity]
  /// by that owner.
  ///
  /// Returns `null` if no valid drive is found.
  Future<Privacy?> getDrivePrivacyForId(String driveId) async {
    final firstOwnerQuery = await _gql.execute(FirstDriveEntityWithIdOwnerQuery(
        variables: FirstDriveEntityWithIdOwnerArguments(driveId: driveId)));

    if (firstOwnerQuery.data!.transactions.edges.isEmpty) {
      return null;
    }

    final driveOwner =
        firstOwnerQuery.data!.transactions.edges.first.node.owner.address;

    final latestDriveQuery = await _gql.execute(LatestDriveEntityWithIdQuery(
        variables: LatestDriveEntityWithIdArguments(
            driveId: driveId, owner: driveOwner)));

    final queryEdges = latestDriveQuery.data!.transactions.edges;
    if (queryEdges.isEmpty) {
      return null;
    }

    final driveTx = queryEdges.first.node;

    return driveTx.getTag(EntityTag.drivePrivacy);
  }

  /// Gets the file privacy of the latest file entity with the provided id.
  ///
  /// This function first checks for the owner of the first instance of the [FileEntity]
  /// with the specified id and then queries for the latest instance of the [FileEntity]
  /// by that owner.
  ///
  /// Returns `null` if no valid file is found.

  Future<Privacy?> getFilePrivacyForId(String fileId) async {
    final firstOwnerQuery = await _gql.execute(FirstFileEntityWithIdOwnerQuery(
        variables: FirstFileEntityWithIdOwnerArguments(fileId: fileId)));

    if (firstOwnerQuery.data!.transactions.edges.isEmpty) {
      return null;
    }

    final fileOwner =
        firstOwnerQuery.data!.transactions.edges.first.node.owner.address;

    final latestFileQuery = await _gql.execute(AllFileEntitiesWithIdQuery(
      variables: AllFileEntitiesWithIdArguments(
        fileId: fileId,
        owner: fileOwner,
      ),
    ));

    final queryEdges = latestFileQuery.data!.transactions.edges;
    if (queryEdges.isEmpty) {
      return null;
    }

    final fileTx = queryEdges.first.node;

    return fileTx.getTag(EntityTag.cipherIv) != null
        ? DrivePrivacy.private
        : DrivePrivacy.public;
  }

  /// Gets the owner of the drive sorted by blockheight.
  /// Returns `null` if no valid drive is found or the provided `driveKey` is incorrect.
  Future<String?> getOwnerForDriveEntityWithId(String driveId) async {
    final firstOwnerQuery = await _graphQLRetry.execute(
        FirstDriveEntityWithIdOwnerQuery(
            variables: FirstDriveEntityWithIdOwnerArguments(driveId: driveId)));

    if (firstOwnerQuery.data!.transactions.edges.isEmpty) {
      return null;
    }

    return firstOwnerQuery.data!.transactions.edges.first.node.owner.address;
  }

  /// Gets any created private drive belonging to [profileId], as long as its unlockable with [password] when used with the [getSignatureFn]
  Future<DriveEntity?> getAnyPrivateDriveEntity(
    String profileId,
    String password,
    Wallet wallet,
  ) async {
    final driveTxs = await getUniqueUserDriveEntityTxs(profileId);
    final privateDriveTxs = driveTxs.where(
        (tx) => tx.getTag(EntityTag.drivePrivacy) == DrivePrivacy.private);

    if (privateDriveTxs.isEmpty) {
      return null;
    }

    final checkDriveId = privateDriveTxs.first.getTag(EntityTag.driveId)!;
    final checkDriveKey = await deriveDriveKey(
      wallet,
      checkDriveId,
      password,
    );

    return await getLatestDriveEntityWithId(
      checkDriveId,
      checkDriveKey,
    );
  }

  /// Gets the latest file entity with the provided id.
  ///
  /// This function first checks for the owner of the first instance of the [FileEntity]
  /// with the specified id and then queries for the latest instance of the [FileEntity]
  /// by that owner.
  ///
  /// Returns `null` if no valid file is found or the provided `fileKey` is incorrect.
  Future<FileEntity?> getLatestFileEntityWithId(String fileId,
      [SecretKey? fileKey]) async {
    final firstOwnerQuery = await _gql.execute(FirstFileEntityWithIdOwnerQuery(
        variables: FirstFileEntityWithIdOwnerArguments(fileId: fileId)));

    if (firstOwnerQuery.data!.transactions.edges.isEmpty) {
      return null;
    }

    final fileOwner =
        firstOwnerQuery.data!.transactions.edges.first.node.owner.address;

    final latestFileQuery = await _gql.execute(LatestFileEntityWithIdQuery(
        variables:
            LatestFileEntityWithIdArguments(fileId: fileId, owner: fileOwner)));

    final queryEdges = latestFileQuery.data!.transactions.edges;
    if (queryEdges.isEmpty) {
      return null;
    }

    final fileTx = queryEdges.first.node;
    final fileDataRes = await client.api.getSandboxedTx(fileTx.id);

    try {
      return await FileEntity.fromTransaction(
        fileTx,
        fileDataRes.bodyBytes,
        fileKey: fileKey,
      );
    } on EntityTransactionParseException catch (parseException) {
      print(
        'Failed to parse transaction '
        'with id ${parseException.transactionId}',
      );
      return null;
    }
  }

  /// Returns the number of confirmations each specified transaction has as a map,
  /// keyed by the transactions' ids.
  ///
  /// When the number of confirmations is 0, the transaction has yet to be mined. When
  /// it is -1, the transaction could not be found.
  Future<Map<String?, int>> getTransactionConfirmations(
      List<String?> transactionIds) async {
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

        final query = await _graphQLRetry.execute(TransactionStatusesQuery(
            variables: TransactionStatusesArguments(
                transactionIds:
                    transactionIds.sublist(i, chunkEnd) as List<String>?)));

        final currentBlockHeight = query.data!.blocks.edges.first.node.height;

        for (final transaction
            in query.data!.transactions.edges.map((e) => e.node)) {
          if (transaction.block == null) {
            transactionConfirmations[transaction.id] = 0;
            continue;
          }

          transactionConfirmations[transaction.id] =
              currentBlockHeight - transaction.block!.height + 1;
        }
      }());
    }

    try {
      await Future.wait(confirmationFutures);
    } catch (e) {
      print('Error getting transactions confirmations on exception: $e');
      rethrow;
    }

    return transactionConfirmations;
  }

  /// Creates and signs a [Transaction] representing the provided entity.
  ///
  /// Optionally provide a [SecretKey] to encrypt the entity data.

  Future<Transaction> prepareEntityTx(
    Entity entity,
    Wallet wallet, [
    SecretKey? key,
  ]) async {
    final tx = await client.transactions.prepare(
      await entity.asTransaction(key),
      wallet,
    );
    await tx.sign(wallet);

    return tx;
  }

  Future<Uint8List> getSignatureData(
    Entity entity,
    Wallet wallet, [
    SecretKey? key,
  ]) async {
    final tx = await client.transactions.prepare(
      await entity.asTransaction(key),
      wallet,
    );

    return await tx.getSignatureData();
  }

  /// Creates and signs a [DataItem] representing the provided entity.
  ///
  /// Optionally provide a [SecretKey] to encrypt the entity data.

  Future<DataItem> prepareEntityDataItem(
    Entity entity,
    Wallet wallet, [
    SecretKey? key,
  ]) async {
    final item = await entity.asDataItem(key);
    item.setOwner(await wallet.getOwner());

    await item.sign(wallet);

    return item;
  }

  /// Creates and signs a [Transaction] representing the provided [DataBundle].

  Future<Transaction> prepareDataBundleTx(
    DataBundle bundle,
    Wallet wallet,
  ) async {
    final packageInfo = await PackageInfo.fromPlatform();

    final bundleTx = await client.transactions.prepare(
      Transaction.withDataBundle(bundleBlob: bundle.blob)
        ..addApplicationTags(version: packageInfo.version),
      wallet,
    );

    await bundleTx.sign(wallet);

    return bundleTx;
  }

  Future<Transaction> prepareDataBundleTxFromBlob(
      Uint8List bundleBlob, Wallet wallet) async {
    final packageInfo = await PackageInfo.fromPlatform();

    final bundleTx = await client.transactions.prepare(
      Transaction.withDataBundle(bundleBlob: bundleBlob)
        ..addApplicationTags(version: packageInfo.version),
      wallet,
    );

    await bundleTx.sign(wallet);

    return bundleTx;
  }

  Future<void> postTx(
    Transaction transaction, {
    bool dryRun = false,
  }) =>
      client.transactions.post(
        transaction,
        dryRun: dryRun,
      );

  Future<double> getArUsdConversionRate() async {
    final client = http.Client();

    return await client
        .get(Uri.parse(
            'https://api.coingecko.com/api/v3/simple/price?ids=arweave&vs_currencies=usd'))
        .then((res) => json.decode(res.body))
        .then((res) => res['arweave']['usd']);
  }
}

/// The entity history of a particular drive, chunked by block height.
class DriveEntityHistory {
  /// A cursor for continuing through this drive's history.
  final String? cursor;
  final int? lastBlockHeight;

  /// A list of block entities, ordered by ascending block height.
  final List<BlockEntities> blockHistory;

  DriveEntityHistory(this.cursor, this.lastBlockHeight, this.blockHistory);
}

/// The entities present in a particular block.
class BlockEntities {
  final int blockHeight;

  /// A list of entities present in this block, ordered by ascending timestamp.
  List<Entity?> entities = <Entity?>[];

  BlockEntities(this.blockHeight);
}

class UploadTransactions {
  Transaction entityTx;
  Transaction dataTx;

  UploadTransactions(this.entityTx, this.dataTx);
}
