import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:ardrive/entities/drive_signature.dart';
import 'package:ardrive/entities/drive_signature_type.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/services/arweave/arweave_service_exception.dart';
import 'package:ardrive/services/arweave/data_gateway_fallback.dart';
import 'package:ardrive/services/arweave/error/gateway_error.dart';
import 'package:ardrive/services/arweave/get_segmented_transaction_from_drive_strategy.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/sync/domain/models/drive_entity_history.dart';
import 'package:ardrive/utils/arfs_txs_filter.dart';
import 'package:ardrive/utils/constants.dart';
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
import 'package:http/http.dart';
import 'package:package_info_plus/package_info_plus.dart';
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
  final ConfigService _configService;
  late ArtemisClient _gql;
  late DataGatewayFallback _gatewayFallback;

  static String _graphqlUrlFromGateway(String gatewayUrl) {
    final uri = Uri.parse(gatewayUrl);
    if (uri.path.endsWith('/graphql')) return gatewayUrl;

    final path = uri.path;
    String newPath;
    if (path.isEmpty || path == '/') {
      newPath = '/graphql';
    } else if (path.endsWith('/')) {
      newPath = '${path}graphql';
    } else {
      newPath = '$path/graphql';
    }
    return uri.replace(path: newPath).toString();
  }

  ArweaveService(
    this.client,
    this._crypto,
    this._driveDao,
    this._configService, {
    ArtemisClient? artemisClient,
  }) : _gql = artemisClient ?? ArtemisClient(_graphqlUrlFromGateway(
            _configService.config.arweaveGatewayUrl ??
                defaultGraphqlGateway)) {
    graphQLRetry = GraphQLRetry(
      _gql,
      internetChecker: InternetChecker(
        connectivity: Connectivity(),
      ),
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
    _gatewayFallback = DataGatewayFallback(
      arioSDK: ArioSDKFactory().create(),
    );
  }

  /// Sets the gateway to use for all Data requests. No GraphQL requests are made with the new gateway.
  void setGateway(Gateway gateway) {
    client = Arweave(api: ArweaveApi(gatewayUrl: getGatewayUri(gateway)));
  }

  /// Updates ONLY the GraphQL endpoint. Does NOT change the data gateway.
  /// Data requests (GET /tx/{id}/data, wallet balance, etc.) continue using
  /// the configured arweaveGatewayForDataRequest.
  void updateGraphQLEndpoint(String gatewayUrl) {
    final previousClient = _gql;
    final graphqlUrl = _graphqlUrlFromGateway(gatewayUrl);
    _gql = ArtemisClient(graphqlUrl);
    graphQLRetry = GraphQLRetry(
      _gql,
      internetChecker: InternetChecker(
        connectivity: Connectivity(),
      ),
    );
    previousClient.dispose();
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
        .get('info')
        .then((res) => json.decode(res.body)['height']);
    if (blockHeight < 0) {
      throw Exception(
          'The current block height $blockHeight is negative. It should be equal or greater than 0.');
    }
    return blockHeight;
  }

  Future<BigInt> getPrice({required int byteSize}) async {
    const maxRetries = 3;
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final res = await client.api.get('price/$byteSize');
        if (res.statusCode == 200) {
          return BigInt.parse(res.body);
        }
        logger.w(
          'getPrice attempt ${attempt + 1} returned ${res.statusCode}',
        );
      } catch (e) {
        logger.w('getPrice attempt ${attempt + 1} failed: $e');
      }
      if (attempt < maxRetries - 1) {
        await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }
    throw Exception('Failed to get price after $maxRetries attempts');
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

  /// Fetches pending (unmined) transactions for a drive.
  /// These are transactions that have been indexed but don't yet have a block.
  /// Used to show Turbo-uploaded files immediately before they're mined.
  Stream<List<DriveEntityHistoryTransactionModel>> getPendingTransactionsForDrive(
    String driveId, {
    required String ownerAddress,
  }) async* {
    String? cursor;
    while (true) {
      try {
        final queryResult = await graphQLRetry.execute(
          PendingDriveEntitiesQuery(
            variables: PendingDriveEntitiesArguments(
              driveId: driveId,
              after: cursor,
              ownerAddress: ownerAddress,
            ),
          ),
        );

        if (queryResult.data == null) {
          logger.w('No data in pending transactions query result');
          break;
        }

        final edges = queryResult.data!.transactions.edges;
        final hasNextPage = queryResult.data!.transactions.pageInfo.hasNextPage;

        // Guard against empty edges with hasNextPage=true causing infinite loop
        if (edges.isEmpty) {
          break;
        }

        // Filter to only include transactions with no block (pending/unmined)
        final pendingTransactions = edges
            .where((edge) => edge.node.block == null)
            .where((edge) => _isSupportedArFSVersion(edge.node))
            .map((e) => DriveEntityHistoryTransactionModel(
                  transactionCommonMixin: e.node,
                  cursor: e.cursor,
                ))
            .toList();

        if (pendingTransactions.isNotEmpty) {
          logger.d('Found ${pendingTransactions.length} pending transactions for drive $driveId');
          yield pendingTransactions;
        }

        // If no more pages, we're done
        if (!hasNextPage) {
          break;
        }

        // If we hit a page with mined transactions, we can stop
        // (since we're sorting HEIGHT_DESC, pending txs appear first)
        final hasMinedTxs = edges.any((edge) => edge.node.block != null);
        if (hasMinedTxs && pendingTransactions.isEmpty) {
          break;
        }

        // Advance cursor for next page
        cursor = edges.last.cursor;
      } catch (e) {
        logger.e('Error fetching pending transactions for drive $driveId', e);
        break;
      }
    }
  }

  bool _isSupportedArFSVersion(TransactionCommonMixin node) {
    final arfsTag =
        node.tags.firstWhereOrNull((tag) => tag.name == EntityTag.arFs);
    return arfsTag != null && supportedArFSVersionsSet.contains(arfsTag.value);
  }

  Stream<List<LicenseAssertions$Query$TransactionConnection$TransactionEdge$Transaction>>
      getLicenseAssertions(
    Iterable<String> licenseAssertionTxIds, {
    String? owner,
  }) async* {
    const chunkSize = 100;
    final chunks = licenseAssertionTxIds.slices(chunkSize);
    for (final chunk in chunks) {
      // Get a page of 100 transactions
      final licenseAssertionsQuery = await graphQLRetry.execute(
        LicenseAssertionsQuery(
          variables: LicenseAssertionsArguments(
            transactionIds: chunk,
            // Scoping by owner narrows the gateway's search space; null leaves
            // the query unscoped (current behavior).
            owners: owner != null ? [owner] : null,
          ),
        ),
      );

      yield licenseAssertionsQuery.data!.transactions.edges
          .map((e) => e.node)
          .toList();
    }
  }

  Stream<List<LicenseComposed$Query$TransactionConnection$TransactionEdge$Transaction>>
      getLicenseComposed(
    Iterable<String> licenseComposedTxIds, {
    String? owner,
  }) async* {
    const chunkSize = 100;
    final chunks = licenseComposedTxIds.slices(chunkSize);
    for (final chunk in chunks) {
      // Get a page of 100 transactions
      final licenseComposedQuery = await graphQLRetry.execute(
        LicenseComposedQuery(
          variables: LicenseComposedArguments(
            transactionIds: chunk,
            // Scoping by owner narrows the gateway's search space; null leaves
            // the query unscoped (current behavior).
            owners: owner != null ? [owner] : null,
          ),
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
    int? currentBlockHeight,
  }) async {
    // Limit concurrent data fetches to avoid overwhelming the gateway.
    // Uses chunked Future.wait — processes maxConcurrent at a time.
    final maxConcurrent =
        _configService.config.maxConcurrentDataFetches.clamp(1, 100);
    final entityDatas = List<Uint8List>.filled(entityTxs.length, Uint8List(0));

    for (var start = 0; start < entityTxs.length; start += maxConcurrent) {
      final end = (start + maxConcurrent < entityTxs.length)
          ? start + maxConcurrent
          : entityTxs.length;

      await Future.wait(
        List.generate(end - start, (j) {
          final i = start + j;
          final entity = entityTxs[i].transactionCommonMixin;
          final tags = HashMap.fromIterable(
            entity.tags,
            key: (tag) => tag.name,
            value: (tag) => tag.value,
          );

          if (driveKey != null && tags[EntityTag.cipherIv] == null) {
            return Future.value();
          }
          if (tags[EntityTag.entityType] == EntityTypeTag.snapshot) {
            return Future.value();
          }

          return _getEntityData(
            entityId: entity.id,
            driveId: driveId,
            isPrivate: driveKey != null,
          ).then((data) {
            entityDatas[i] = data;
          });
        }),
      );
    }

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

      // Process unmined transactions using currentBlockHeight
      // They appear "as of now" and will be updated when actually mined
      // Transaction status system handles pending → confirmed transition
      final blockHeight = transaction.block?.height
          ?? currentBlockHeight
          ?? lastBlockHeight;

      if (blockHistory.isEmpty ||
          blockHistory.last.blockHeight != blockHeight) {
        blockHistory.add(BlockEntities(blockHeight));
      }

      try {
        final entityType = tags[EntityTag.entityType];
        final rawEntityData = entityDatas[i];

        if (rawEntityData.isNotEmpty) {
          await metadataCache.put(transaction.id, rawEntityData);
        }

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
    final Response data = await _gatewayFallback.fetchData(txId, client);
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

  Future<TransactionCommonMixin?> getFirstPrivateDriveTx(
    Wallet wallet, {
    int maxRetries = defaultMaxRetries,
  }) async {
    final driveTxs = await getUniqueUserDriveEntityTxs(
      await wallet.getAddress(),
      maxRetries: maxRetries,
    );

    final privateDriveTxs = driveTxs.where(
        (tx) => tx.getTag(EntityTag.drivePrivacy) == DrivePrivacyTag.private);

    final firstTx = privateDriveTxs.isNotEmpty ? privateDriveTxs.first : null;

    return firstTx;
  }

  Future<DriveSignatureEntity?> getDriveSignatureForDrive(
    Wallet wallet,
    String driveId,
  ) async {
    final driveSignatureTx = await getDriveSignatureTxForDrive(wallet, driveId);

    final driveSignatureData = driveSignatureTx != null
        ? await _gatewayFallback.fetchData(driveSignatureTx.id, client)
        : null;

    final driveSignature =
        driveSignatureTx != null && driveSignatureData != null
            ? DriveSignatureEntity.fromTransaction(
                driveSignatureTx, driveSignatureData.bodyBytes)
            : null;
    return driveSignature;
  }

  /// Gets the unique drive entities for a particular user.
  Future<Map<DriveEntity, DriveKey?>> getUniqueUserDriveEntities(
    Wallet wallet,
    String password,
  ) async {
    try {
      final userAddress = await wallet.getAddress();
      final driveTxs = await getUniqueUserDriveEntityTxs(userAddress);

      final driveResponses = await Future.wait(
        driveTxs.map((e) => _gatewayFallback
            .fetchData(e.id, client)
            .then<Response?>((r) => r)
            .catchError((_) => null)),
      );

      final drivesById = <String?, DriveEntity>{};
      final drivesWithKey = <DriveEntity, DriveKey?>{};
      for (var i = 0; i < driveTxs.length; i++) {
        if (driveResponses[i] == null) continue;
        final driveTx = driveTxs[i];

        // Ignore drive entity transactions which we already have newer entities for.
        if (drivesById.containsKey(driveTx.getTag(EntityTag.driveId))) {
          continue;
        }

        DriveKey? driveKey;

        if (driveTx.getTag(EntityTag.drivePrivacy) == DrivePrivacyTag.private) {
          driveKey = await _driveDao.getDriveKeyFromMemory(
            driveTx.getTag(EntityTag.driveId)!,
          );

          if (driveKey == null) {
            final sigTypeTag = driveTx.getTag(EntityTag.signatureType) ?? '1';
            final signatureType = DriveSignatureType.fromString(sigTypeTag);

            final driveSignature = signatureType == DriveSignatureType.v1
                ? await getDriveSignatureForDrive(
                    wallet, driveTx.getTag(EntityTag.driveId)!)
                : null;

            driveKey = await _crypto.deriveDriveKey(
                wallet,
                driveTx.getTag(EntityTag.driveId)!,
                password,
                signatureType,
                driveSignature);

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
            driveResponses[i]!.bodyBytes,
            driveKey?.key,
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
      final fileDataRes = await _gatewayFallback.fetchData(fileTx.id, client);

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
    final signatureType = DriveSignatureType.fromString(
        privateDriveTxs.first.getTag(EntityTag.signatureType) ?? '1');

    final driveSignature = signatureType == DriveSignatureType.v1
        ? await getDriveSignatureForDrive(wallet, checkDriveId)
        : null;

    final checkDriveKey = await _crypto.deriveDriveKey(
        wallet, checkDriveId, password, signatureType, driveSignature);

    return await getLatestDriveEntityWithId(
      checkDriveId,
      driveOwner: await wallet.getAddress(),
      driveKey: checkDriveKey.key,
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
      final fileDataRes = await _gatewayFallback.fetchData(fileTx.id, client);

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
        final fileDataRes =
            await _gatewayFallback.fetchData(fileTx.id, client);

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
  /// [ownerOverrides] maps a transaction id to the address that actually owns
  /// it on-chain when that differs from [owner] (e.g. the data tx of a file
  /// pinned from another author's upload). Any id left unresolved by the
  /// owner-scoped pass that has an override is re-queried scoped to its real
  /// owner — keeping every query selective. Ids with no override are left
  /// unresolved rather than re-queried unscoped, which would reintroduce the
  /// expensive gateway scan this scoping is meant to avoid.
  ///
  /// [verifiedSink], if provided, is progressively populated with each
  /// successfully verified confirmation (value >= 0) as the query completes —
  /// it never receives the -1 "not found" placeholders. A caller can wrap this
  /// method in a timeout and, on expiry, fall back to [verifiedSink] to keep
  /// the confirmations resolved so far instead of discarding the whole batch.
  /// Because it holds only positive verifications, applying it after a timeout
  /// never marks anything failed off an incomplete run.
  Future<Map<String?, int>> getTransactionConfirmations(
    List<String?> transactionIds, {
    String? owner,
    Map<String, String>? ownerOverrides,
    Map<String?, int>? verifiedSink,
  }) async {
    final transactionConfirmations = {
      for (final transactionId in transactionIds) transactionId: -1
    };

    // Queries confirmation status for [ids] in chunks, writing results into
    // [transactionConfirmations] (and [verifiedSink] for resolved ids). When
    // [owner] is provided, the query is scoped to that owner so the gateway can
    // prune its search space.
    Future<void> queryConfirmations(List<String?> ids, {String? owner}) async {
      const chunkSize = 100;
      // Cap how many chunk queries hit the gateway at once so a large page
      // doesn't fan out into a burst of concurrent GraphQL retries (and a
      // potential rate-limit storm), matching the throttling used by the other
      // gateway-heavy paths in this service.
      final maxConcurrent =
          _configService.config.maxConcurrentDataFetches.clamp(1, 100);

      Future<void> queryChunk(int start) async {
        final chunkEnd =
            (start + chunkSize < ids.length) ? start + chunkSize : ids.length;

        final query = await graphQLRetry.execute(
          TransactionStatusesQuery(
            variables: TransactionStatusesArguments(
              transactionIds:
                  ids.sublist(start, chunkEnd).whereType<String>().toList(),
              owners: owner != null ? [owner] : null,
            ),
          ),
        );

        final currentBlockHeight = query.data!.blocks.edges.first.node.height;

        for (final transaction
            in query.data!.transactions.edges.map((e) => e.node)) {
          final confirmations = transaction.block == null
              ? 0
              : currentBlockHeight - transaction.block!.height + 1;
          transactionConfirmations[transaction.id] = confirmations;
          // Record the resolved verification so it survives a caller timeout.
          verifiedSink?[transaction.id] = confirmations;
        }
      }

      final chunkStarts = [for (var i = 0; i < ids.length; i += chunkSize) i];
      // Process the chunks in bounded-concurrency batches.
      for (var b = 0; b < chunkStarts.length; b += maxConcurrent) {
        final batch = chunkStarts.skip(b).take(maxConcurrent);
        try {
          await Future.wait(batch.map(queryChunk));
        } catch (e) {
          logger.e('Error getting transactions confirmations on exception', e);
          rethrow;
        }
      }
    }

    // First pass: scoped by owner for gateway selectivity.
    await queryConfirmations(transactionIds, owner: owner);

    // Second pass: for any unresolved id whose real owner we know locally
    // (currently pinned data txs), re-query scoped to that owner. This recovers
    // confirmed cross-owner txs without an unscoped scan. Genuinely missing txs
    // have no override and are left unresolved — handled by the caller's
    // existing pending/failed logic.
    //
    // Best-effort: this pass must never discard the first pass's results. Its
    // results are merged into the already-populated map, so we swallow any
    // error and bound it with its own timeout — even if it fails or stalls,
    // the confirmations resolved by the first pass are still returned.
    if (owner != null && ownerOverrides != null && ownerOverrides.isNotEmpty) {
      final idsByOverrideOwner = <String, List<String?>>{};
      for (final entry in transactionConfirmations.entries) {
        if (entry.value >= 0) continue;
        final overrideOwner = ownerOverrides[entry.key];
        if (overrideOwner == null || overrideOwner == owner) continue;
        idsByOverrideOwner.putIfAbsent(overrideOwner, () => []).add(entry.key);
      }

      if (idsByOverrideOwner.isNotEmpty) {
        try {
          await Future(() async {
            for (final entry in idsByOverrideOwner.entries) {
              await queryConfirmations(entry.value, owner: entry.key);
            }
          }).timeout(const Duration(seconds: 3));
        } catch (e) {
          logger.w(
            'Pinned-owner confirmation recovery failed or timed out; '
            'leaving those txs unresolved: $e',
          );
        }
      }
    }

    return transactionConfirmations;
  }

  Future<String?> getFirstTxForWallet(String owner) async {
    final firstTxForWalletQuery = await graphQLRetry.execute(
      FirstTxForWalletQuery(
        variables: FirstTxForWalletArguments(owner: owner),
      ),
    );

    if (firstTxForWalletQuery.data!.transactions.edges.isEmpty) {
      return null;
    }

    return firstTxForWalletQuery.data!.transactions.edges.first.node.id;
  }

  Future<TransactionCommonMixin?> getDriveSignatureTxForDrive(
    Wallet wallet,
    String driveId, {
    int maxRetries = defaultMaxRetries,
  }) async {
    final driveSignatureTxs = await graphQLRetry.execute(
      DriveSignatureForDriveQuery(
        variables: DriveSignatureForDriveArguments(
          owner: await wallet.getAddress(),
          driveId: driveId,
        ),
      ),
    );

    if (driveSignatureTxs.data!.transactions.edges.isEmpty) {
      return null;
    }

    return driveSignatureTxs.data!.transactions.edges.first.node;
  }

  Future<List<(String, int)>?> getTransactionsAtHeight(
      String owner, int height) async {
    final transactionsAtHeightQuery = await graphQLRetry.execute(
      TransactionsAtHeightQuery(
        variables: TransactionsAtHeightArguments(
          owner: owner,
          height: height,
        ),
      ),
    );

    if (transactionsAtHeightQuery.data!.transactions.edges.isEmpty) {
      return null;
    }

    return transactionsAtHeightQuery.data!.transactions.edges
        .map((e) => (e.node.id, int.parse(e.node.data.size)))
        .toList();
  }

  Future<int?> getFirstTxBlockHeightForWallet(String owner) async {
    final firstTxBlockHeightForWalletQuery = await graphQLRetry.execute(
      FirstTxBlockHeightForWalletQuery(
        variables: FirstTxBlockHeightForWalletArguments(owner: owner),
      ),
    );

    if (firstTxBlockHeightForWalletQuery.data!.transactions.edges.isEmpty) {
      return null;
    }

    return firstTxBlockHeightForWalletQuery
        .data!.transactions.edges.first.node.block?.height;
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

  /// Uploads a transaction using the same chunked flow as file data uploads:
  /// header then chunks with [maxConcurrentUploadCount] (default 1) to avoid
  /// gateway 400s from data_root propagation when many chunk requests hit
  /// before the tx is indexed.
  Future<void> uploadTx(
    Transaction transaction, {
    int maxConcurrentUploadCount = 1,
    bool dryRun = false,
  }) async {
    await client.transactions
        .upload(
          transaction,
          maxConcurrentUploadCount: maxConcurrentUploadCount,
          dryRun: dryRun,
        )
        .drain();
  }

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

    final Response data = await _gatewayFallback.fetchData(txId, client);
    final metadata = data.bodyBytes;
    return metadata;
  }

  /// Fetches transaction info for multiple transactions in batches.
  /// Returns a stream of transaction info batches.
  Stream<Map<String, TxInfo>> getInfoOfTxsToBePinned(
    List<String> transactionIds, {
    int batchSize = 5,
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

class TransactionNotFound implements Exception {
  final String txId;

  TransactionNotFound(this.txId);
}
