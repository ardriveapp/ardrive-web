import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/services/arweave/arweave_service_exception.dart';
import 'package:ardrive/services/arweave/error/gateway_error.dart';
import 'package:ardrive/services/arweave/get_segmented_transaction_from_drive_strategy.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/sync/domain/models/drive_entity_history.dart';
import 'package:ardrive/utils/arfs_txs_filter.dart';
import 'package:ardrive/utils/graphql_retry.dart';
import 'package:ardrive/utils/http_retry.dart';
import 'package:ardrive/utils/internet_checker.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/metadata_cache.dart';
import 'package:ardrive/utils/snapshots/snapshot_item.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:artemis/artemis.dart';
import 'package:arweave/arweave.dart';
import 'package:collection/collection.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:http/http.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:retry/retry.dart';
import 'package:stash_shared_preferences/stash_shared_preferences.dart';

import 'error/gateway_response_handler.dart';

typedef SnapshotEntityTransaction
    = SnapshotEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction;
typedef TxInfo
    = InfoOfTransactionsToBePinned$Query$TransactionConnection$TransactionEdge$Transaction;
const byteCountPerChunk = 262144; // 256 KiB
const defaultMaxRetries = 8;
const kMaxNumberOfTransactionsPerPage = 100;

class ArweaveService {
  Arweave client;
  final ArDriveCrypto _crypto;
  final DriveDao _driveDao;
  final ArtemisClient _gql;

  ArweaveService(
    this.client,
    this._crypto,
    this._driveDao,
    ConfigService configService, {
    ArtemisClient? artemisClient,
  }) : _gql = artemisClient ??
            ArtemisClient(
                '${configService.config.defaultArweaveGatewayUrl}/graphql') {
    graphQLRetry = GraphQLRetry(
      _gql,
      internetChecker: InternetChecker(
        connectivity: Connectivity(),
      ),
      arioSDK: ArioSDKFactory().create(),
    );
    httpRetry = HttpRetry(
      GatewayResponseHandler(),
      HttpRetryOptions(
        onRetry: (exception) {
          if (exception is GatewayError) {
            logger.w(
              'Retrying for ${exception.runtimeType} exception'
              ' for route ${exception.requestUrl}'
              ' and status code ${exception.statusCode}',
            );
            return;
          }

          logger.w('Retrying for unknown exception');
        },
        retryIf: (exception) {
          return exception is! RateLimitError;
        },
      ),
    );
  }

  /// Sets the gateway to use for all Data requests. No GraphQL requests are made with the new gateway.
  void setGateway(Gateway gateway) {
    client = Arweave(gatewayUrl: getGatewayUri(gateway));
  }

  int bytesToChunks(int bytes) {
    return (bytes / byteCountPerChunk).ceil();
  }

  late GraphQLRetry graphQLRetry;
  late HttpRetry httpRetry;

  /// Returns the onchain balance of the specified address.
  Future<BigInt> getWalletBalance(String address) => client.api
      .get('wallet/$address/balance')
      .then((res) => BigInt.parse(res.body));

  Future<int> getCurrentBlockHeight() async {
    //TODO (Javed) Use GQL Query to fetch block height
    final blockHeight = await client.api
        .get('/')
        .then((res) => json.decode(res.body)['height']);
    if (blockHeight < 0) {
      throw Exception(
          'The current block height $blockHeight is negative. It should be equal or greater than 0.');
    }
    return blockHeight;
  }

  Future<BigInt> getPrice({required int byteSize}) async {
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
    final query = await graphQLRetry.execute(
      PendingTxFeesQuery(
        variables: PendingTxFeesArguments(
          walletAddress: address,
        ),
      ),
    );

    if (query.data == null) {
      throw ArweaveServiceException(
          'Error fetching pending transaction fees. The query `PendingTxFeesQuery` returned null');
    }

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

  Future<InfoOfTransactionToBePinned$Query$Transaction?> getInfoOfTxToBePinned(
    String txId,
  ) async {
    final query = await _gql.execute(InfoOfTransactionToBePinnedQuery(
        variables: InfoOfTransactionToBePinnedArguments(txId: txId)));
    return query.data?.transaction;
  }

  Stream<SnapshotEntityTransaction> getAllSnapshotsOfDrive(
    String driveId,
    int? lastBlockHeight, {
    required String ownerAddress,
  }) async* {
    String cursor = '';

    while (true) {
      try {
        // Get a page of 100 transactions
        final snapshotEntityHistoryQuery = await graphQLRetry.execute(
          SnapshotEntityHistoryQuery(
            variables: SnapshotEntityHistoryArguments(
              driveId: driveId,
              lastBlockHeight: lastBlockHeight,
              after: cursor,
              ownerAddress: ownerAddress,
            ),
          ),
        );
        for (SnapshotEntityHistory$Query$TransactionConnection$TransactionEdge edge
            in snapshotEntityHistoryQuery.data!.transactions.edges) {
          yield edge.node;
        }

        cursor = snapshotEntityHistoryQuery.data!.transactions.edges.isNotEmpty
            ? snapshotEntityHistoryQuery.data!.transactions.edges.last.cursor
            : '';

        if (!snapshotEntityHistoryQuery
            .data!.transactions.pageInfo.hasNextPage) {
          break;
        }
      } catch (e) {
        logger.e('Error fetching snapshots for drive $driveId', e);
        logger.i('This drive and ones after will fall back to GQL');
        break;
      }
    }
  }

  Stream<List<DriveEntityHistoryTransactionModel>>
      getSegmentedTransactionsFromDrive(
    String driveId, {
    required String ownerAddress,
    int? minBlockHeight,
    int? maxBlockHeight,
    GetSegmentedTransactionFromDriveStrategy? strategy,
  }) async* {
    strategy ??=
        GetSegmentedTransactionFromDriveWithoutEntityTypeFilterStrategy(
      graphQLRetry,
    );

    logger.d(
        'Fetching segmented transactions from drive using strategy ${strategy.runtimeType}');

    yield* strategy.getSegmentedTransactionFromDrive(
      driveId,
      minBlockHeight: minBlockHeight,
      maxBlockHeight: maxBlockHeight,
      ownerAddress: ownerAddress,
    );
  }

  Stream<List<LicenseAssertions$Query$TransactionConnection$TransactionEdge$Transaction>>
      getLicenseAssertions(Iterable<String> licenseAssertionTxIds) async* {
    const chunkSize = 100;
    final chunks = licenseAssertionTxIds.slices(chunkSize);
    for (final chunk in chunks) {
      // Get a page of 100 transactions
      final licenseAssertionsQuery = await graphQLRetry.execute(
        LicenseAssertionsQuery(
          variables: LicenseAssertionsArguments(transactionIds: chunk),
        ),
      );

      yield licenseAssertionsQuery.data!.transactions.edges
          .map((e) => e.node)
          .toList();
    }
  }

  Stream<List<LicenseComposed$Query$TransactionConnection$TransactionEdge$Transaction>>
      getLicenseComposed(Iterable<String> licenseComposedTxIds) async* {
    const chunkSize = 100;
    final chunks = licenseComposedTxIds.slices(chunkSize);
    for (final chunk in chunks) {
      // Get a page of 100 transactions
      final licenseComposedQuery = await graphQLRetry.execute(
        LicenseComposedQuery(
          variables: LicenseComposedArguments(transactionIds: chunk),
        ),
      );

      yield licenseComposedQuery.data!.transactions.edges
          .map((e) => e.node)
          .where((e) => e.tags.any((t) => t.name == 'License'))
          .toList();
    }
  }

  /// Get the metadata of transactions
  ///
  /// mounts the `blockHistory`
  ///
  /// returns DriveEntityHistory object
  Future<DriveEntityHistory> createDriveEntityHistoryFromTransactions(
    List<DriveEntityHistoryTransactionModel> entityTxs,
    SecretKey? driveKey,
    int lastBlockHeight, {
    required String ownerAddress,
    required DriveID driveId,
  }) async {
    // FIXME - PE-3440
    /// Make use of `eagerError: true` to make it fail on first error
    /// Also, when there's no internet connection and when we're getting
    /// rate-limited (TODO: check the latter), many requests will be retrying.
    /// We shall find another way to fail faster.

    // MAYBE FIX: set a narrow concurrency limit

    final List<Uint8List> entityDatas = await Future.wait(
      entityTxs.map(
        (model) async {
          final entity = model.transactionCommonMixin;

          final tags = HashMap.fromIterable(
            entity.tags,
            key: (tag) => tag.name,
            value: (tag) => tag.value,
          );

          if (driveKey != null && tags[EntityTag.cipherIv] == null) {
            logger.d('skipping unnecessary request for a broken entity');
            return Uint8List(0);
          }

          final isSnapshot =
              tags[EntityTag.entityType] == EntityTypeTag.snapshot;

          // don't fetch data for snapshots
          if (isSnapshot) {
            logger.d('skipping unnecessary request for snapshot data');
            return Uint8List(0);
          }

          return _getEntityData(
            entityId: entity.id,
            driveId: driveId,
            isPrivate: driveKey != null,
          );
        },
      ),
    );

    final metadataCache = await MetadataCache.fromCacheStore(
      await newSharedPreferencesCacheStore(),
    );

    final blockHistory = <BlockEntities>[];

    for (var i = 0; i < entityTxs.length; i++) {
      final transaction = entityTxs[i].transactionCommonMixin;

      final tags = HashMap.fromIterable(
        transaction.tags,
        key: (tag) => tag.name,
        value: (tag) => tag.value,
      );

      if (driveKey != null && tags[EntityTag.cipherIv] == null) {
        logger.d('skipping unnecessary request for a broken entity');
        continue;
      }

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
        final entityType = tags[EntityTag.entityType];
        final rawEntityData = entityDatas[i];

        await metadataCache.put(transaction.id, rawEntityData);

        Entity? entity;
        if (entityType == EntityTypeTag.drive) {
          entity = await DriveEntity.fromTransaction(
              transaction, _crypto, rawEntityData, driveKey);
        } else if (entityType == EntityTypeTag.folder) {
          entity = await FolderEntity.fromTransaction(
              transaction, _crypto, rawEntityData, driveKey);
        } else if (entityType == EntityTypeTag.file) {
          entity = await FileEntity.fromTransaction(
            transaction,
            rawEntityData,
            driveKey: driveKey,
            crypto: _crypto,
          );

          if (entity is FileEntity) {
            if (entity.assignedNames != null) {
              logger
                  .d('FileEntity has assigned names: ${entity.assignedNames}');
            }
          }
        } else if (entityType == EntityTypeTag.snapshot) {
          // TODO: instantiate entity and add to blockHistory
        }

        // TODO: Revisit
        if (blockHistory.isEmpty ||
            transaction.block!.height != blockHistory.last.blockHeight) {
          blockHistory.add(BlockEntities(transaction.block!.height));
        }

        blockHistory.last.entities.add(entity);

        // If there are errors in parsing the entity, ignore it.
      } on EntityTransactionParseException catch (parseException) {
        logger.w(
          'Failed to parse transaction '
          'with id ${parseException.transactionId}',
        );
      } on GatewayError catch (fetchException) {
        logger.e(
          'Failed to fetch entity data with the exception ${fetchException.runtimeType}'
          ' for transaction ${transaction.id}, '
          ' with status ${fetchException.statusCode} '
          ' and reason ${fetchException.reasonPhrase}',
        );
      }
    }

    // Sort the entities in each block by ascending commit time.
    for (final block in blockHistory) {
      block.entities.removeWhere((e) => e == null);
      block.entities.sort((e1, e2) => e1!.createdAt.compareTo(e2!.createdAt));
      //Remove entities with spoofed owners
      block.entities.removeWhere((e) => e!.ownerAddress != ownerAddress);
    }

    return DriveEntityHistory(
      blockHistory.isNotEmpty ? blockHistory.last.blockHeight : lastBlockHeight,
      blockHistory,
    );
  }

  Future<bool> hasUserPrivateDrives(
    Wallet wallet, {
    int maxRetries = defaultMaxRetries,
  }) async {
    final driveTxs = await getUniqueUserDriveEntityTxs(
      await wallet.getAddress(),
      maxRetries: maxRetries,
    );

    final privateDriveTxs = driveTxs.where(
        (tx) => tx.getTag(EntityTag.drivePrivacy) == DrivePrivacyTag.private);

    return privateDriveTxs.isNotEmpty;
  }

  Future<Uint8List> _getEntityData({
    required String entityId,
    required String driveId,
    required bool isPrivate,
  }) async {
    final txId = entityId;

    final cachedData = await _getCachedEntityDataFromSnapshot(
      driveId: driveId,
      txId: txId,
      isPrivate: isPrivate,
    );

    if (cachedData != null) {
      return cachedData;
    }

    return getEntityDataFromNetwork(txId: txId).catchError((e) {
      logger.e('Failed to get entity data from network', e);
      return Uint8List(0);
    });
  }

  Future<Uint8List?> _getCachedEntityDataFromSnapshot({
    required String txId,
    required String driveId,
    required bool isPrivate,
  }) async {
    try {
      final Uint8List? cachedData = await SnapshotItemOnChain.getDataForTxId(
        driveId,
        txId,
      );

      if (cachedData != null) {
        if (isPrivate) {
          // then it's base64-encoded
          return base64.decode(String.fromCharCodes(cachedData));
        } else {
          // public data is plain text
          return cachedData;
        }
      }
    } catch (e) {
      logger.e('Failed to get cached entity data from snapshot', e);
    }

    return null;
  }

  Future<Uint8List> getEntityDataFromNetwork({required String txId}) async {
    final Response data =
        (await httpRetry.processRequest(() => client.api.getSandboxedTx(txId)));

    return data.bodyBytes;
  }

  // Gets the unique drive entity transactions for a particular user.
  Future<List<TransactionCommonMixin>> getUniqueUserDriveEntityTxs(
    String userAddress, {
    int maxRetries = defaultMaxRetries,
  }) async {
    List<TransactionCommonMixin> drives = [];
    String cursor = '';

    while (true) {
      final userDriveEntitiesQuery = await graphQLRetry.execute(
        UserDriveEntitiesQuery(
          variables: UserDriveEntitiesArguments(
            owner: userAddress,
            after: cursor,
          ),
        ),
        maxAttempts: maxRetries,
      );

      final queryEdges = userDriveEntitiesQuery.data!.transactions.edges;
      final filteredEdges = queryEdges.where(
        (element) => doesTagsContainValidArFSVersion(
          element.node.tags.map((e) => Tag(e.name, e.value)).toList(),
        ),
      );

      cursor = queryEdges.isNotEmpty ? queryEdges.last.cursor : '';

      final drivesInThisPage = filteredEdges
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

      drives.addAll(drivesInThisPage);

      final hasNextPage =
          userDriveEntitiesQuery.data!.transactions.pageInfo.hasNextPage;
      if (!hasNextPage) {
        break;
      }
    }

    return drives;
  }

  Future<String?> getFirstPrivateDriveTxId(
    Wallet wallet, {
    int maxRetries = defaultMaxRetries,
  }) async {
    final driveTxs = await getUniqueUserDriveEntityTxs(
      await wallet.getAddress(),
      maxRetries: maxRetries,
    );

    final privateDriveTxs = driveTxs.where(
        (tx) => tx.getTag(EntityTag.drivePrivacy) == DrivePrivacyTag.private);

    return privateDriveTxs.isNotEmpty
        ? privateDriveTxs.first.getTag(EntityTag.driveId)!
        : null;
  }

  /// Gets the unique drive entities for a particular user.
  Future<Map<DriveEntity, SecretKey?>> getUniqueUserDriveEntities(
    Wallet wallet,
    String password,
  ) async {
    try {
      final userAddress = await wallet.getAddress();
      final driveTxs = await getUniqueUserDriveEntityTxs(userAddress);

      final driveResponses = await retry(
          () async => await Future.wait(
                driveTxs.map((e) => client.api.getSandboxedTx(e.id)),
              ), onRetry: (Exception err) {
        logger.w('Retrying for get unique user drive entities');
      });

      final drivesById = <String?, DriveEntity>{};
      final drivesWithKey = <DriveEntity, SecretKey?>{};
      for (var i = 0; i < driveTxs.length; i++) {
        final driveTx = driveTxs[i];

        // Ignore drive entity transactions which we already have newer entities for.
        if (drivesById.containsKey(driveTx.getTag(EntityTag.driveId))) {
          continue;
        }

        SecretKey? driveKey;

        if (driveTx.getTag(EntityTag.drivePrivacy) == DrivePrivacyTag.private) {
          driveKey = await _driveDao.getDriveKeyFromMemory(
            driveTx.getTag(EntityTag.driveId)!,
          );

          if (driveKey == null) {
            driveKey = await _crypto.deriveDriveKey(
              wallet,
              driveTx.getTag(EntityTag.driveId)!,
              password,
            );

            _driveDao.putDriveKeyInMemory(
              driveID: driveTx.getTag(EntityTag.driveId)!,
              driveKey: driveKey,
            );
          }
        }
        try {
          final drive = await DriveEntity.fromTransaction(
            driveTx,
            _crypto,
            driveResponses[i].bodyBytes,
            driveKey,
          );

          drivesById[drive.id] = drive;
          drivesWithKey[drive] = driveKey;

          // If there's an error parsing the drive entity, just ignore it.
        } on EntityTransactionParseException catch (parseException) {
          logger.e(
            'Failed to parse transaction '
            'with id ${parseException.transactionId}',
            parseException,
          );
        }
      }
      return drivesWithKey;
    } catch (e, stacktrace) {
      logger.e(
        'An error occurred when getting the unique user drive entities.',
        e,
        stacktrace,
      );
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
    String driveId, {
    String? driveOwner,
    SecretKey? driveKey,
    int maxRetries = defaultMaxRetries,
  }) async {
    driveOwner ??= await getOwnerForDriveEntityWithId(driveId);

    if (driveOwner == null) {
      return null;
    }

    String cursor = '';
    while (true) {
      final latestDriveQuery = await graphQLRetry.execute(
        LatestDriveEntityWithIdQuery(
          variables: LatestDriveEntityWithIdArguments(
            driveId: driveId,
            owner: driveOwner,
            after: cursor,
          ),
        ),
        maxAttempts: maxRetries,
      );

      final queryEdges = latestDriveQuery.data!.transactions.edges;
      if (queryEdges.isEmpty) {
        return null;
      }

      final filteredEdges = queryEdges.where(
        (element) => doesTagsContainValidArFSVersion(
          element.node.tags.map((e) => Tag(e.name, e.value)).toList(),
        ),
      );

      final hasNextPage =
          latestDriveQuery.data!.transactions.pageInfo.hasNextPage;

      if (filteredEdges.isEmpty) {
        if (hasNextPage) {
          cursor = latestDriveQuery.data!.transactions.edges.last.cursor;
          continue;
        } else {
          return null;
        }
      }

      final fileTx = filteredEdges.first.node;
      final fileDataRes = await client.api.getSandboxedTx(fileTx.id);

      try {
        return await DriveEntity.fromTransaction(
            fileTx, _crypto, fileDataRes.bodyBytes, driveKey);
      } on EntityTransactionParseException catch (parseException) {
        logger.e(
          'Failed to parse transaction '
          'with id ${parseException.transactionId}',
          parseException,
        );
        return null;
      }
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
    final driveOwner = await getOwnerForDriveEntityWithId(driveId);
    if (driveOwner == null) {
      return null;
    }

    final latestDriveQuery = await graphQLRetry.execute(
        LatestDriveEntityWithIdQuery(
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
    final fileOwner = await getOwnerForFileEntityWithId(fileId);
    if (fileOwner == null) {
      return null;
    }

    String cursor = '';

    while (true) {
      final latestFileQuery = await _gql.execute(
        LatestFileEntityWithIdQuery(
          variables: LatestFileEntityWithIdArguments(
            fileId: fileId,
            owner: fileOwner,
            after: cursor,
          ),
        ),
      );

      final queryEdges = latestFileQuery.data!.transactions.edges;

      if (queryEdges.isEmpty) {
        return null;
      }

      final filteredEdges = queryEdges.where(
        (element) => doesTagsContainValidArFSVersion(
          element.node.tags.map((e) => Tag(e.name, e.value)).toList(),
        ),
      );

      final hasNextPage =
          latestFileQuery.data!.transactions.pageInfo.hasNextPage;

      if (filteredEdges.isEmpty) {
        if (hasNextPage) {
          cursor = latestFileQuery.data!.transactions.edges.last.cursor;
          continue;
        } else {
          return null;
        }
      }

      final fileTx = filteredEdges.first.node;

      return fileTx.getTag(EntityTag.cipherIv) != null
          ? DrivePrivacyTag.private
          : DrivePrivacyTag.public;
    }
  }

  /// Gets the owner of the drive sorted by blockheight.
  /// Returns `null` if no valid drive is found or the provided `driveKey` is incorrect.
  Future<String?> getOwnerForDriveEntityWithId(
    String driveId,
  ) async {
    String cursor = '';

    while (true) {
      final firstOwnerQuery = await graphQLRetry.execute(
        FirstDriveEntityWithIdOwnerQuery(
          variables: FirstDriveEntityWithIdOwnerArguments(
            driveId: driveId,
            after: cursor,
          ),
        ),
      );

      if (firstOwnerQuery.data!.transactions.edges.isEmpty) {
        return null;
      }

      final List<
              FirstDriveEntityWithIdOwner$Query$TransactionConnection$TransactionEdge>
          filteredEdges = firstOwnerQuery.data!.transactions.edges
              .where(
                (element) => doesTagsContainValidArFSVersion(
                  element.node.tags.map((e) => Tag(e.name, e.value)).toList(),
                ),
              )
              .toList();

      final hasNextPage =
          firstOwnerQuery.data!.transactions.pageInfo.hasNextPage;

      if (filteredEdges.isEmpty) {
        if (hasNextPage) {
          cursor = firstOwnerQuery.data!.transactions.edges.last.cursor;
          continue;
        } else {
          return null;
        }
      }

      return filteredEdges.first.node.owner.address;
    }
  }

  /// Gets any created private drive belonging to [profileId], as long as its unlockable with [password] when used with the [getSignatureFn]
  Future<DriveEntity?> getAnyPrivateDriveEntity(
    String profileId,
    String password,
    Wallet wallet,
  ) async {
    final driveTxs = await getUniqueUserDriveEntityTxs(profileId);
    final privateDriveTxs = driveTxs.where(
        (tx) => tx.getTag(EntityTag.drivePrivacy) == DrivePrivacyTag.private);

    if (privateDriveTxs.isEmpty) {
      return null;
    }

    final checkDriveId = privateDriveTxs.first.getTag(EntityTag.driveId)!;
    final checkDriveKey = await _crypto.deriveDriveKey(
      wallet,
      checkDriveId,
      password,
    );

    return await getLatestDriveEntityWithId(
      checkDriveId,
      driveOwner: await wallet.getAddress(),
      driveKey: checkDriveKey,
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
    final fileOwner = await getOwnerForFileEntityWithId(fileId);
    if (fileOwner == null) {
      return null;
    }

    String cursor = '';

    while (true) {
      final latestFileQuery = await graphQLRetry.execute(
        LatestFileEntityWithIdQuery(
          variables: LatestFileEntityWithIdArguments(
            fileId: fileId,
            owner: fileOwner,
            after: cursor,
          ),
        ),
      );

      final queryEdges = latestFileQuery.data!.transactions.edges;
      if (queryEdges.isEmpty) {
        return null;
      }

      final filteredEdges = queryEdges.where(
        (element) => doesTagsContainValidArFSVersion(
          element.node.tags.map((e) => Tag(e.name, e.value)).toList(),
        ),
      );
      if (filteredEdges.isEmpty) {
        cursor = queryEdges.last.cursor;
        continue;
      }

      final fileTx = filteredEdges.first.node;
      final fileDataRes = await client.api.getSandboxedTx(fileTx.id);

      try {
        return await FileEntity.fromTransaction(
          fileTx,
          fileDataRes.bodyBytes,
          fileKey: fileKey,
          crypto: _crypto,
        );
      } on EntityTransactionParseException catch (parseException) {
        logger.e(
          'Failed to parse transaction '
          'with id ${parseException.transactionId}',
        );
        return null;
      }
    }
  }

  Future<List<FileEntity>?> getAllFileEntitiesWithId(String fileId,
      [SecretKey? fileKey]) async {
    String? cursor;
    int? lastBlockHeight;
    List<FileEntity> fileEntities = [];

    final fileOwner = await getOwnerForFileEntityWithId(fileId);
    if (fileOwner == null) {
      return null;
    }

    while (true) {
      // Get a page of 100 transactions
      final allFileEntitiesQuery = await graphQLRetry.execute(
        AllFileEntitiesWithIdQuery(
          variables: AllFileEntitiesWithIdArguments(
            fileId: fileId,
            owner: fileOwner,
            lastBlockHeight: lastBlockHeight,
            after: cursor,
          ),
        ),
      );
      final List<
              AllFileEntitiesWithId$Query$TransactionConnection$TransactionEdge>
          queryEdges = allFileEntitiesQuery.data!.transactions.edges
              .where(
                (element) => doesTagsContainValidArFSVersion(
                  element.node.tags.map((e) => Tag(e.name, e.value)).toList(),
                ),
              )
              .toList();
      if (queryEdges.isEmpty) {
        break;
      }
      for (var edge in queryEdges) {
        final fileTx = edge.node;
        final fileDataRes = await client.api.getSandboxedTx(fileTx.id);

        try {
          fileEntities.add(
            await FileEntity.fromTransaction(
              fileTx,
              fileDataRes.bodyBytes,
              fileKey: fileKey,
              crypto: _crypto,
            ),
          );
        } on EntityTransactionParseException catch (parseException) {
          logger.e(
            'Failed to parse transaction with id ${parseException.transactionId}',
            parseException,
          );
        }
      }

      cursor = queryEdges.last.cursor;

      if (!allFileEntitiesQuery.data!.transactions.pageInfo.hasNextPage) {
        break;
      }
    }

    return fileEntities.isEmpty ? null : fileEntities;
  }

  Future<String?> getOwnerForFileEntityWithId(
    FileID fileId,
  ) async {
    FirstFileEntityWithIdOwner$Query;
    String cursor = '';

    while (true) {
      final firstOwnerQuery = await graphQLRetry.execute(
        FirstFileEntityWithIdOwnerQuery(
          variables: FirstFileEntityWithIdOwnerArguments(
            fileId: fileId,
            after: cursor,
          ),
        ),
      );

      if (firstOwnerQuery.data!.transactions.edges.isEmpty) {
        return null;
      }

      final filteredEdges = firstOwnerQuery.data!.transactions.edges
          .where(
            (element) => doesTagsContainValidArFSVersion(
              element.node.tags.map((e) => Tag(e.name, e.value)).toList(),
            ),
          )
          .toList();

      final hasNextPage =
          firstOwnerQuery.data!.transactions.pageInfo.hasNextPage;

      if (filteredEdges.isEmpty) {
        if (hasNextPage) {
          cursor = firstOwnerQuery.data!.transactions.edges.last.cursor;
          continue;
        } else {
          return null;
        }
      }

      final fileOwner = filteredEdges.first.node.owner.address;
      return fileOwner;
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

    const chunkSize = 100;

    final confirmationFutures = <Future<void>>[];

    for (var i = 0; i < transactionIds.length; i += chunkSize) {
      confirmationFutures.add(() async {
        final chunkEnd = (i + chunkSize < transactionIds.length)
            ? i + chunkSize
            : transactionIds.length;

        final query = await graphQLRetry.execute(
          TransactionStatusesQuery(
            variables: TransactionStatusesArguments(
              transactionIds:
                  transactionIds.sublist(i, chunkEnd) as List<String>?,
            ),
          ),
        );

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
      logger.e('Error getting transactions confirmations on exception', e);
      rethrow;
    }

    return transactionConfirmations;
  }

  Future<String?> getFirstTxForWallet(String owner) async {
    final firstTxQuery = await graphQLRetry.execute(
      FirstTxForWalletQuery(
        variables: FirstTxForWalletArguments(owner: owner),
      ),
    );

    if (firstTxQuery.data!.transactions.edges.isEmpty) {
      return null;
    }

    return firstTxQuery.data!.transactions.edges.first.node.id;
  }

  /// Creates and signs a [Transaction] representing the provided entity.
  ///
  /// Optionally provide a [SecretKey] to encrypt the entity data.

  Future<Transaction> prepareEntityTx(
    Entity entity,
    Wallet wallet,
    SecretKey? key, {
    bool skipSignature = false,
  }) async {
    final tx = await client.transactions.prepare(
      await entity.asTransaction(key: key),
      wallet,
    );

    if (!skipSignature) {
      await tx.sign(ArweaveSigner(wallet));
    }

    return tx;
  }

  /// Creates and signs a [DataItem] representing the provided entity.
  ///
  /// Optionally provide a [SecretKey] to encrypt the entity data.

  Future<DataItem> prepareEntityDataItem(
    Entity entity,
    Wallet wallet, {
    SecretKey? key,
    bool skipSignature = false,
  }) async {
    final item = await entity.asDataItem(key);
    item.setOwner(await wallet.getOwner());

    if (!skipSignature) {
      await item.sign(ArweaveSigner(wallet));
    }

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
        ..addApplicationTags(
          version: packageInfo.version,
        ),
      wallet,
    );

    await bundleTx.sign(ArweaveSigner(wallet));

    return bundleTx;
  }

  /// Creates and signs a [DataItem] with a [DataBundle] as payload.
  /// Allows us to create nested bundles for use with the upload service.

  Future<DataItem> prepareBundledDataItem(
    DataBundle bundle,
    Wallet wallet,
  ) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final item = DataItem.withBlobData(data: bundle.blob)
      ..addApplicationTags(
        version: packageInfo.version,
      )
      ..addBundleTags()
      ..setOwner(await wallet.getOwner());
    await item.sign(ArweaveSigner(wallet));

    logger.i('Prepared bundled data item with id ${item.id}'
        ' with tags ${item.tags}');

    return item;
  }

  Future<Transaction> prepareDataBundleTxFromBlob(
      Uint8List bundleBlob, Wallet wallet) async {
    final packageInfo = await PackageInfo.fromPlatform();

    final bundleTx = await client.transactions.prepare(
      Transaction.withDataBundle(bundleBlob: bundleBlob)
        ..addApplicationTags(version: packageInfo.version)
        ..addUTags(),
      wallet,
    );

    await bundleTx.sign(ArweaveSigner(wallet));

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

  // TODO: replace with the method on ardrive_utils
  Future<double?> getArUsdConversionRateOrNull() async {
    try {
      return await getArUsdConversionRate();
    } catch (e) {
      return null;
    }
  }

  // TODO: replace with the method on ardrive_utils
  Future<double> getArUsdConversionRate() async {
    const String coinGeckoApi =
        'https://api.coingecko.com/api/v3/simple/price?ids=arweave&vs_currencies=usd';

    final response = await ArDriveHTTP(retries: 3).getJson(coinGeckoApi);

    return response.data?['arweave']['usd'];
  }

  Future<Uint8List> dataFromTxId(
    String txId,
    SecretKey? driveKey,
  ) async {
    // TODO: PE-2917

    final Response data =
        (await httpRetry.processRequest(() => client.api.getSandboxedTx(txId)));
    final metadata = data.bodyBytes;
    return metadata;
  }

  /// Fetches transaction info for multiple transactions in batches.
  /// Returns a stream of transaction info batches.
  Stream<Map<String, TxInfo>> getInfoOfTxsToBePinned(
    List<String> transactionIds, {
    int batchSize = 10,
  }) async* {
    for (var i = 0; i < transactionIds.length; i += batchSize) {
      final end = (i + batchSize < transactionIds.length)
          ? i + batchSize
          : transactionIds.length;
      final batch = transactionIds.sublist(i, end);

      logger.i('Fetching transaction info for batch ${batch.length}');

      try {
        final query = await _gql.execute(
          InfoOfTransactionsToBePinnedQuery(
            variables: InfoOfTransactionsToBePinnedArguments(
              transactionIds: batch,
            ),
          ),
        );

        if (query.data != null) {
          final batchResults = <String, TxInfo>{};
          for (final edge in query.data!.transactions.edges) {
            final tx = edge.node;
            batchResults[tx.id] = tx;
          }
          logger.d('Batch results length: ${batchResults.length}');
          yield batchResults;
        }
      } catch (e) {
        logger.e('Failed to fetch transaction info batch', e);
        // Continue with next batch even if one fails
      }
    }
  }
}

/// The entity history of a particular drive, chunked by block height.
class DriveEntityHistory {
  final int? lastBlockHeight;

  /// A list of block entities, ordered by ascending block height.
  final List<BlockEntities> blockHistory;

  DriveEntityHistory(this.lastBlockHeight, this.blockHistory);
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
