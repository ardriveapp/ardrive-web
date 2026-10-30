import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:ardrive/entities/drive_signature.dart';
import 'package:ardrive/entities/drive_signature_type.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/locked_drives/domain/drive_unlocker.dart';
import 'package:ardrive/locked_drives/domain/locked_drive.dart';
import 'package:ardrive/locked_drives/domain/user_drive_discovery.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/permanence/permanence_cache.dart';
import 'package:ardrive/services/arweave/arweave_service_exception.dart';
import 'package:ardrive/services/arweave/data_gateway_fallback.dart';
import 'package:ardrive/services/arweave/error/gateway_error.dart';
import 'package:ardrive/services/arweave/fragment_free_graphql.dart';
import 'package:ardrive/services/arweave/get_segmented_transaction_from_drive_strategy.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/sync/domain/models/drive_entity_history.dart';
import 'package:ardrive/utils/arfs_txs_filter.dart';
import 'package:ardrive/utils/constants.dart';
import 'package:ardrive/permanence/ar_spend.dart';
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
import 'package:retry/retry.dart';
import 'package:stash_shared_preferences/stash_shared_preferences.dart';

import 'error/gateway_response_handler.dart';

typedef SnapshotEntityTransaction
    = SnapshotEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction;
const byteCountPerChunk = 262144; // 256 KiB
const defaultMaxRetries = 8;
const kMaxNumberOfTransactionsPerPage = 100;

/// How many transaction ids may go into one GraphQL query's `ids` argument.
///
/// Nine, because that is what the fallback endpoint accepts, and every query
/// that chunks ids can end up there: `GraphQLRetry` falls back to Goldsky on a
/// 429 or a 5xx, and Goldsky answers a longer list with
/// `Too many ids in 'ids' argument: N provided, maximum 9 allowed`.
///
/// So a hundred was not merely wrong when Goldsky is configured as the primary
/// endpoint. It made the fallback decorative for these queries on *every*
/// configuration: the sync hits a rate limit on the primary, switches to the
/// endpoint that exists to rescue it, and is refused for the shape of the
/// request rather than for anything the endpoint could not answer.
///
/// The cost of the smaller batch is small where it is paid. Statuses are only
/// asked for transactions not already known to be confirmed, so the list is
/// short in an ordinary sync - the report that found this was 31 ids, which is
/// four requests rather than one.
const int maxGraphQLIdsPerQuery = 9;

/// Entity types a drive's history carries that sync never parses, so never
/// fetches. They share the drive's `Drive-Id`, so the unfiltered history
/// query returns them, and each body would otherwise be downloaded and kept
/// in the metadata cache (local storage on the web) on every first sync: a
/// snapshot or drive state runs to megabytes, a publication's manifest to
/// about 82 KB. Their own readers find them by GraphQL and fetch them
/// themselves (drive-state discovery, `PublicationRepository`).
const _entityTypesSyncNeverReads = {
  EntityTypeTag.snapshot,
  EntityTypeTag.driveState,
  EntityTypeTag.publication,
};

/// Whether sync downloads the body of the entity with [tags], before any
/// request is made: never for an entity type it does not parse, nor for a
/// private drive's entity with no `Cipher-IV` (broken, unreadable).
@visibleForTesting
bool syncFetchesEntityData(
  Map<Object?, Object?> tags, {
  required bool isPrivateDrive,
}) {
  if (isPrivateDrive && tags[EntityTag.cipherIv] == null) return false;
  return !_entityTypesSyncNeverReads.contains(tags[EntityTag.entityType]);
}

class ArweaveService {
  Arweave client;
  final ArDriveCrypto _crypto;
  final ConfigService _configService;
  late ArtemisClient _gql;
  late DataGatewayFallback _gatewayFallback;
  DataGatewayFallback get gatewayFallback => _gatewayFallback;

  /// For the requests this service makes itself rather than through [client]
  /// or GraphQL. Injectable so they can be tested without a network.
  final Client _httpClient;

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

  /// [driveDao] is no longer read: drive discovery's keys come from the
  /// `resolvePrivateDriveKey` its caller passes. Kept so the many callers
  /// that build this service don't change.
  ArweaveService(
    this.client,
    this._crypto,
    // ignore: avoid_unused_constructor_parameters
    DriveDao driveDao,
    this._configService, {
    ArtemisClient? artemisClient,
    Client? httpClient,
  })  : _httpClient = httpClient ?? Client(),
        _gql = artemisClient ??
            fragmentFreeArtemisClient(_graphqlUrlFromGateway(
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
    _gql = fragmentFreeArtemisClient(graphqlUrl);
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

  /// Cache for [getUniqueUserDriveEntityTxs] to avoid redundant GQL calls.
  /// Auth flow (isExistingUser, _validateUser) and sync (updateUserDrives)
  /// all call this for the same wallet. Invalidated explicitly via
  /// [clearUserDriveTxsCache] when a drive is created/updated or after sync.
  String? _cachedUserDriveTxsAddress;
  List<TransactionCommonMixin>? _cachedUserDriveTxs;

  /// When each of the cached user's drives was created: the commit time of
  /// its oldest drive transaction, keyed by drive id. Filled and cleared with
  /// [_cachedUserDriveTxs]. See [cachedUserDriveCreationTimes].
  Map<String, DateTime>? _cachedUserDriveCreationTimes;

  /// Cache for raw entity data bytes fetched during [getUniqueUserDriveEntities].
  /// Keyed by transaction ID. Allows [getLatestDriveEntityWithId] to re-parse
  /// the data with a different key without re-downloading from the gateway.
  final Map<String, Uint8List> _cachedEntityDataBytes = {};

  /// Cache for drive signatures (immutable on-chain, never change).
  final Map<String, DriveSignatureEntity?> _cachedDriveSignatures = {};

  /// Entity metadata reads served from a drive's snapshot, and those that had
  /// to go to the gateway instead. Keyed by drive id, reported by sync when a
  /// drive finishes. See [_getEntityData].
  final Map<String, int> snapshotMetadataHits = {};
  final Map<String, int> snapshotMetadataMisses = {};

  final _userDriveTxPages = StreamController<String>.broadcast(sync: true);

  /// The wallet address of each page [getUniqueUserDriveEntityTxs] receives,
  /// as it arrives. A wallet with many drives takes many pages: a caller with
  /// a deadline uses this to tell one that is still arriving from a gateway
  /// that stopped answering.
  Stream<String> get userDriveTxPageReceived => _userDriveTxPages.stream;

  /// Clears the cached result of [getUniqueUserDriveEntityTxs] and entity data.
  /// Call after creating/updating a drive or after a full sync completes.
  void clearUserDriveTxsCache() {
    _cachedUserDriveTxsAddress = null;
    _cachedUserDriveTxs = null;
    _cachedUserDriveCreationTimes = null;
    _cachedEntityDataBytes.clear();
  }

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

  /// How long one price request may take before the attempt is abandoned.
  ///
  /// Without this the retry loop below cannot do its job: `client.api.get` has
  /// no deadline, so an attempt that hangs rather than fails hangs for ever and
  /// the second and third attempts are never reached. The loop reads as if it
  /// were resilient while being exactly as fragile as a single call.
  ///
  /// Six seconds so the three bounded calls behind one AR cost estimate - this,
  /// the community tip and the AR/USD rate - still fit inside that estimate's
  /// own 20-second budget.
  static const _priceAttemptTimeout = Duration(seconds: 6);

  Future<BigInt> getPrice({required int byteSize}) async {
    const maxRetries = 3;
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final res = await client.api
            .get('price/$byteSize')
            .timeout(_priceAttemptTimeout);
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

  /// The tags, owner address, block and bundle of a transaction.
  ///
  /// This is the query the cipher path runs: the preview reads `Cipher` and
  /// `Cipher-IV` off it to decrypt, and the download reads the same two. It
  /// selects nothing else, because every field it selects is a field a gateway
  /// can break it with.
  ///
  /// It used to be the same request as [getTransactionDetailsWithSignature],
  /// which also selects `signature`, `anchor`, `recipient` and `ownerKey` for
  /// the data item integrity check. The schema declares all four non-null, and
  /// this code assumed a gateway that does not index one would answer with an
  /// empty string. Some answer with `null`, and Artemis then fails
  /// deserialization for the *entire* query - taking the cipher tags with it,
  /// and with them every private preview and private download on that gateway.
  ///
  /// What is remembered is the transaction's tags, owner and bundle, which do
  /// not change. `block` is on it too and *does* - it is null until the
  /// transaction is mined - so a caller that wants mined status must ask
  /// somewhere else rather than read it off a memo that may predate the block.
  /// Nothing does today.
  Future<TransactionCommonMixin?> getTransactionDetails(String txId) {
    final cached = _transactionDetails[txId];

    if (cached != null) {
      return cached;
    }

    final request = graphQLRetry
        .execute(TransactionDetailsQuery(
            variables: TransactionDetailsArguments(txId: txId)))
        .then((query) => query.data?.transaction)
        // Bounded here rather than at each call site, because the memo is what
        // makes an unbounded read dangerous: the entry is only removed once the
        // future settles, so a request that never does is handed to every later
        // caller for the life of this service - one hang poisoning one
        // transaction forever. `GraphQLRetry` has no timeout of its own; it
        // spends ~6s of backoff on the primary and then retries a fallback, so
        // this is a backstop well clear of a slow-but-working read, not a UX
        // deadline. Callers that need a tighter one still apply it themselves.
        .timeout(_transactionDetailsTimeout);

    // The future is held, not the result, so callers that arrive together share
    // one request rather than starting a second while the first is in flight -
    // which is exactly what a preview and the download behind it do.
    _transactionDetails[txId] = request;

    return request.then((transaction) {
      // An answer is kept; a miss is not. A transaction that could not be read
      // may be a rate limit, a gateway that has not indexed it yet, or one that
      // never will, and none of those is a fact worth remembering. `null` is
      // also what a not-yet-mined transaction returns, and the page retries
      // those on purpose.
      if (transaction == null) {
        _transactionDetails.remove(txId);
      } else {
        _rememberTransaction(txId);
      }

      return transaction;
    }, onError: (Object error, StackTrace stackTrace) {
      _transactionDetails.remove(txId);

      throw error;
    });
  }

  /// Everything [getTransactionDetails] returns, plus what it takes to
  /// recompute a data item's deep hash signature: `signature`, `ownerKey.key`
  /// (the owner's full public key), `anchor` and `recipient` (the data item's
  /// target).
  ///
  /// `bundledIn != null` marks an L2 data item, the only case where those four
  /// fields describe an ANS-104 deep hash. For an L1 transaction they describe
  /// the L1 transaction itself, whose integrity comes from its `data_root`
  /// instead.
  ///
  /// A separate request from [getTransactionDetails], and deliberately so. The
  /// schema declares those four non-null, but a gateway that does not index
  /// them answers `null` and fails deserialization for the whole query. A
  /// caller here is asking for verification and can be told it is unavailable;
  /// the cipher path cannot, so it does not select them at all.
  ///
  /// Not memoized: nothing in the app calls this today - the data item
  /// integrity check is off - and a verification is worth its own request when
  /// one is asked for.
  Future<TransactionDetailsWithSignature$Query$Transaction?>
      getTransactionDetailsWithSignature(String txId) async {
    final query = await graphQLRetry.execute(
        TransactionDetailsWithSignatureQuery(
            variables: TransactionDetailsWithSignatureArguments(txId: txId)));

    return query.data?.transaction;
  }

  /// Transaction details already asked for, by transaction id.
  ///
  /// A transaction is immutable: its tags, owner and bundle are the same
  /// answer every time, so asking twice is never anything but a second round
  /// trip. Two callers on the shared file page ask for the same one - the
  /// preview, to read the cipher it decrypts with, and the download behind it
  /// for the same tags - and before this they each paid for it. On a connection
  /// the gateway rate limits, the second is the one that fails.
  final Map<String, Future<TransactionCommonMixin?>> _transactionDetails = {};

  /// Insertion order, so the oldest entry is the one evicted.
  final List<String> _transactionDetailsOrder = [];

  /// How many transactions to remember.
  ///
  /// Small on purpose. This exists to stop one page asking the same question
  /// twice, not to be a cache of the chain, and a recipient page looks at one
  /// file.
  static const _maxRememberedTransactions = 64;

  /// How long a memoized transaction read may stay in flight.
  ///
  /// Generous, because it is the backstop that guarantees the memo entry
  /// settles rather than a deadline anyone waits on - the retry ladder plus a
  /// fallback endpoint can legitimately take tens of seconds on a bad
  /// connection, and cutting that short would turn a slow read into a failed
  /// one.
  static const _transactionDetailsTimeout = Duration(seconds: 60);

  void _rememberTransaction(String txId) {
    _transactionDetailsOrder.remove(txId);
    _transactionDetailsOrder.add(txId);

    while (_transactionDetailsOrder.length > _maxRememberedTransactions) {
      _transactionDetails.remove(_transactionDetailsOrder.removeAt(0));
    }
  }

  Future<InfoOfTransactionToBePinned$Query$Transaction?> getInfoOfTxToBePinned(
    String txId,
  ) async {
    final query = await graphQLRetry.execute(InfoOfTransactionToBePinnedQuery(
        variables: InfoOfTransactionToBePinnedArguments(txId: txId)));
    return query.data?.transaction;
  }

  /// Fetch snapshots for a single drive. Delegates to [getAllSnapshotsForDrives].
  Stream<SnapshotEntityTransaction> getAllSnapshotsOfDrive(
    String driveId,
    int? lastBlockHeight, {
    required String ownerAddress,
  }) =>
      getAllSnapshotsForDrives([driveId], lastBlockHeight,
          ownerAddress: ownerAddress);

  /// Fetch snapshots for multiple drives in a single paginated GQL query.
  ///
  /// Use [minBlockHeight] = min of all drives' lastBlockHeights.
  /// Caller should filter results by Drive-Id tag and pass each drive's
  /// subset to [SnapshotItem.instantiateAll] with that drive's own
  /// lastBlockHeight to preserve per-drive state isolation.
  /// [onQueryFailure] fires if the query gave up part-way.
  ///
  /// The stream ends the same way either way - a failure is logged and the
  /// iteration stops - so a caller cannot otherwise tell "this drive has no
  /// snapshots" from "we stopped asking". The batched prefetch needs that
  /// distinction: without it, every snapshot-less drive looks unanswered and
  /// gets asked again individually.
  Stream<SnapshotEntityTransaction> getAllSnapshotsForDrives(
    List<String> driveIds,
    int? minBlockHeight, {
    required String ownerAddress,
    void Function()? onQueryFailure,
  }) async* {
    String cursor = '';
    var yielded = 0;
    var page = 0;

    while (true) {
      try {
        final snapshotEntityHistoryQuery = await graphQLRetry.execute(
          SnapshotEntityHistoryQuery(
            variables: SnapshotEntityHistoryArguments(
              driveIds: driveIds,
              lastBlockHeight: minBlockHeight,
              after: cursor,
              ownerAddress: ownerAddress,
            ),
          ),
        );
        final edges = snapshotEntityHistoryQuery.data!.transactions.edges;
        page++;
        yielded += edges.length;

        // What the index actually returned, before anything downstream
        // filters it. This is the number that separates "the gateway did not
        // tell us about the snapshot" from "we knew about it and could not
        // use it" - the two have completely different fixes, and without this
        // they look identical from the outside.
        logger.i('[snapshot] gql page $page for $driveIds (min block '
            '$minBlockHeight): ${edges.length} found');

        for (final edge in edges) {
          yield edge.node;
        }

        // Guard against empty edges with hasNextPage=true causing infinite loop
        if (edges.isEmpty) {
          break;
        }

        cursor = edges.last.cursor;

        if (!snapshotEntityHistoryQuery
            .data!.transactions.pageInfo.hasNextPage) {
          break;
        }
      } catch (e) {
        // Note what was already yielded: the caller keeps those, so a failure
        // here can leave a drive with *some* of its snapshots - typically the
        // newest, since the query is HEIGHT_DESC - rather than none. That
        // reads downstream as a smaller snapshot than expected rather than an
        // error, so the count matters as much as the exception.
        logger.e(
          '[snapshot] gql failed for $driveIds after $yielded found '
          'across $page page(s); those already found are still used, the '
          'rest of the range falls back to GraphQL',
          e,
        );
        onQueryFailure?.call();
        break;
      }
    }

    logger.i('[snapshot] gql returned $yielded total for $driveIds');
  }

  /// Probes which drives have any new transactions since [minBlockHeight].
  /// Returns the set of drive IDs with activity. If the query returns
  /// hasNextPage=true, the result is incomplete — caller should treat
  /// un-checked drives as potentially active.
  Future<({Set<String> activeDriveIds, bool isComplete})> probeActiveDriveIds({
    required List<String> driveIds,
    required int minBlockHeight,
    required String ownerAddress,
    Map<String, int>? readUpTo,
    Future<Set<String>> Function(List<String> txIds)? knownTxIds,
  }) async {
    final query = await graphQLRetry.execute(
      DriveActivityProbeQuery(
        variables: DriveActivityProbeArguments(
          driveIds: driveIds,
          minBlockHeight: minBlockHeight,
          ownerAddress: ownerAddress,
        ),
      ),
    );

    if (query.data == null) {
      // Treat as incomplete — caller will fall back to syncing all drives
      return (activeDriveIds: <String>{}, isComplete: false);
    }

    final edges = query.data!.transactions.edges;

    // What this device holds already: read by a sync, or written here and
    // not yet read back. Neither is a change nobody has seen.
    final known = knownTxIds == null
        ? const <String>{}
        : await knownTxIds([for (final edge in edges) edge.node.id]);

    final activeDriveIds = <String>{};
    for (final edge in edges) {
      if (known.contains(edge.node.id)) continue;
      final height = edge.node.block?.height;
      final tags = {for (final tag in edge.node.tags) tag.name: tag.value};
      final driveId = tags['Drive-Id'];
      if (driveId == null) continue;

      // One query covers drives read up to different heights, from below
      // the lowest of them. Past a drive's own height anything new counts;
      // at or below it, only drive, folder and file metadata this device
      // doesn't hold, which a gateway indexed after the drive was read.
      // Other entities there (snapshots, drive signatures) are never kept
      // as rows, so they would count again after every reload.
      final readTo = readUpTo?[driveId];
      if (readTo != null && height != null && height <= readTo) {
        final entityType = tags['Entity-Type'];
        if (entityType != 'drive' &&
            entityType != 'folder' &&
            entityType != 'file') {
          continue;
        }
      }
      activeDriveIds.add(driveId);
    }

    final isComplete = !query.data!.transactions.pageInfo.hasNextPage;
    return (activeDriveIds: activeDriveIds, isComplete: isComplete);
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
  Stream<List<DriveEntityHistoryTransactionModel>>
      getPendingTransactionsForDrive(
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
          logger.d(
              'Found ${pendingTransactions.length} pending transactions for drive $driveId');
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
    const chunkSize = maxGraphQLIdsPerQuery;
    final chunks = licenseAssertionTxIds.slices(chunkSize);
    for (final chunk in chunks) {
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
    const chunkSize = maxGraphQLIdsPerQuery;
    final chunks = licenseComposedTxIds.slices(chunkSize);
    for (final chunk in chunks) {
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

  /// Runs [task] for every index in `0..itemCount-1`, keeping at most
  /// [concurrency] in flight and starting the next index as soon as any one
  /// completes.
  ///
  /// This is a sliding window, not a chunked `Future.wait`. A chunked barrier
  /// idles every other slot until the slowest member of the chunk returns, so
  /// one slow or failing item costs the whole chunk its duration.
  ///
  /// [task] owns its error handling — a task that throws aborts the run.
  ///
  /// [onItemDone] is called once for every task that returns, at the moment it
  /// returns, before its worker claims the next index. It is the only thing
  /// inside this loop that a caller can see move: the run itself reports
  /// nothing until all of it is over, and for metadata fetches that is one
  /// HTTP round trip per item at [concurrency] at a time — the longest silence
  /// in a sync. Counting is the caller's job; this says only "one more is
  /// done", so the hook cannot be read as a total the pool does not own.
  ///
  /// It must not throw and it must not await: it runs between a slot being
  /// released and the next index being claimed, so anything slow here is
  /// concurrency taken away from the fetches.
  ///
  /// Also how sign-in reads the private drives it checks the password on.
  static Future<void> runPooled({
    required int concurrency,
    required int itemCount,
    required Future<void> Function(int index) task,
    void Function()? onItemDone,
  }) async {
    if (itemCount <= 0) return;

    final workerCount = concurrency < 1
        ? 1
        : (concurrency < itemCount ? concurrency : itemCount);

    // Shared cursor. Claiming an index is synchronous, so two workers can
    // never take the same one.
    var nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        final i = nextIndex;
        if (i >= itemCount) return;
        nextIndex++;
        await task(i);
        onItemDone?.call();
      }
    }

    await Future.wait(List.generate(workerCount, (_) => worker()));
  }

  /// Get the metadata of transactions
  ///
  /// mounts the `blockHistory`
  ///
  /// returns DriveEntityHistory object
  ///
  /// [onEntityFetched] fires once per entity in [entityTxs], as each one is
  /// finished with rather than when the batch is. It is the sync's only view
  /// into this loop: every entity's metadata body is one HTTP round trip, run
  /// `maxConcurrentDataFetches` at a time, and a drive with three thousand
  /// revisions spends nearly the whole of its "reading the drive history" here
  /// with nothing else to report.
  Future<DriveEntityHistory> createDriveEntityHistoryFromTransactions(
    List<DriveEntityHistoryTransactionModel> entityTxs,
    SecretKey? driveKey,
    int lastBlockHeight, {
    required String ownerAddress,
    required DriveID driveId,
    int? currentBlockHeight,
    void Function()? onEntityFetched,
  }) async {
    // Limit concurrent data fetches to avoid overwhelming the gateway.
    //
    // Sliding window, not chunked Future.wait: workers pull the next index as
    // soon as they finish, so exactly maxConcurrent fetches stay in flight.
    // A chunked barrier would idle every other slot until the slowest member
    // of the chunk returned — and with the 2-attempt sync retry, one dead
    // transaction stalls its whole chunk for ~10s.
    final maxConcurrent =
        _configService.config.maxConcurrentDataFetches.clamp(1, 100);
    final entityDatas = List<Uint8List>.filled(entityTxs.length, Uint8List(0));

    /// Metadata reads that failed outright. These entities are skipped for
    /// this sync — see the note on [_getEntityData] for why that can be a
    /// permanent drop, and `docs/SYNC_SKIPPED_ENTITY_PERSISTENCE.md` for the
    /// planned fix. Surfaced so callers can report them instead of losing them.
    final skippedTxIds = <String>[];

    await runPooled(
      concurrency: maxConcurrent,
      itemCount: entityTxs.length,
      // One per entity, whether its body was fetched, skipped or already in
      // hand - the caller is counting how much of the batch is behind it, not
      // how many requests were made, so an entity that costs no request still
      // has to land. Without that the count would stop short of the total on
      // any batch holding a snapshot or a broken private entity.
      onItemDone: onEntityFetched,
      task: (i) async {
        final entity = entityTxs[i].transactionCommonMixin;
        final tags = HashMap.fromIterable(
          entity.tags,
          key: (tag) => tag.name,
          value: (tag) => tag.value,
        );

        // Entities we never fetch. Leave entityDatas[i] at its empty default
        // and release the slot immediately.
        if (!syncFetchesEntityData(tags, isPrivateDrive: driveKey != null)) {
          return;
        }

        // _getEntityData never throws — a failed read skips only this entity
        // and must never abort the run.
        final data = await _getEntityData(
          entityId: entity.id,
          driveId: driveId,
          isPrivate: driveKey != null,
        );

        if (data == null) {
          skippedTxIds.add(entity.id);
          return;
        }

        // Positional write — callers rely on entityDatas aligning with
        // entityTxs, so results are never appended.
        entityDatas[i] = data;
      },
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

      // Process unmined transactions using currentBlockHeight
      // They appear "as of now" and will be updated when actually mined
      // Transaction status system handles pending → confirmed transition
      final blockHeight =
          transaction.block?.height ?? currentBlockHeight ?? lastBlockHeight;

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

    if (skippedTxIds.isNotEmpty) {
      logger.w(
        'Skipped ${skippedTxIds.length} entities in drive $driveId: their '
        'metadata could not be read. They will not appear in this sync.',
      );
    }

    return DriveEntityHistory(
      blockHistory.isNotEmpty ? blockHistory.last.blockHeight : lastBlockHeight,
      blockHistory,
      skippedTxIds: skippedTxIds,
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

  /// Returns the entity's metadata bytes, or `null` if they could not be read.
  ///
  /// KNOWN ISSUE — a `null` here is a silent, potentially permanent drop, and
  /// it predates the single-gateway sync change. The caller substitutes empty
  /// bytes, the entity fails to parse (swallowed at the `on
  /// EntityTransactionParseException` in
  /// [createDriveEntityHistoryFromTransactions]) and never reaches
  /// `blockHistory` — while the drive's watermark advances regardless. Only a
  /// user-initiated deep sync reliably recovers it.
  ///
  /// Full evidence and the planned fix (persist skipped items and retry them
  /// across syncs) are in `docs/SYNC_SKIPPED_ENTITY_PERSISTENCE.md`. Until
  /// then the tx ids are at least reported on `SyncProgress` rather than lost.
  Future<Uint8List?> _getEntityData({
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
      snapshotMetadataHits.update(driveId, (v) => v + 1, ifAbsent: () => 1);
      return cachedData;
    }

    // Every miss is a network round trip for a few hundred bytes, and sync
    // makes one of these per entity. Whether a drive's entities come from its
    // snapshot or from the gateway is the difference between one download and
    // tens of thousands of requests, and until now nothing said which was
    // happening. Counted rather than logged per entity: at 40k entities a log
    // line each would be the slowest part of the sync.
    snapshotMetadataMisses.update(driveId, (v) => v + 1, ifAbsent: () => 1);

    return getEntityDataFromNetwork(txId: txId)
        .then<Uint8List?>((d) => d)
        .catchError((e) {
      logger.e('Failed to get entity data from network for tx $txId', e);
      return null;
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

  /// Reads entity metadata for the **sync** path.
  ///
  /// Uses [DataGatewayFallback.fetchDataForSync] — configured gateway only,
  /// one retry, one last-resort hop, no GAR and therefore no Solana RPC.
  /// Download/preview/thumbnail/share paths keep the full waterfall.
  /// [largeBody] gives the read the budget a snapshot needs. The default is
  /// sized for metadata - a few hundred bytes - and a snapshot body is tens of
  /// megabytes, which cannot finish inside it at any realistic connection
  /// speed. See [DataGatewayFallback.largeBodyRequestTimeout].
  Future<Uint8List> getEntityDataFromNetwork({
    required String txId,
    bool largeBody = false,
  }) async {
    final Response data = await _gatewayFallback.fetchDataForSync(
      txId,
      client,
      largeBody: largeBody,
    );
    return data.bodyBytes;
  }

  /// The most drive revisions [getDriveEntityRevisions] will read: two pages
  /// of the history query. A drive is renamed or hidden a handful of times,
  /// so this is never reached by a real one; it bounds what a tab opening
  /// can cost.
  static const maxDriveRevisionsRead = 200;

  /// Every revision of a drive's own entity, oldest first: its creation and
  /// each rename, hide and unhide, without its folders or files.
  ///
  /// For showing the history of a drive that has not been synced on this
  /// device. It only reads: nothing is stored, so a later sync starts from
  /// exactly where it would have.
  ///
  /// Ordered as sync orders them, by block height, pending last, then by
  /// commit time inside a block. A revision that does not parse, or whose
  /// owner is not [ownerAddress], is left out, as sync leaves it out.
  ///
  /// `null` when the history could not be read: the query failed, any
  /// revision's metadata could not be fetched, there are more than
  /// [maxDriveRevisionsRead], or [isCancelled] said to stop. A fetch that
  /// fails is not skipped, because a missing first revision would make the
  /// next one read as the creation. The first failure stops the reads still
  /// to start.
  Future<List<DriveEntity>?> getDriveEntityRevisions(
    String driveId, {
    required String ownerAddress,
    SecretKey? driveKey,
    bool Function()? isCancelled,
  }) async {
    bool stopped() => isCancelled?.call() ?? false;

    final txs = <TransactionCommonMixin>[];

    try {
      String? cursor;
      while (true) {
        final result = await graphQLRetry.execute(
          DriveEntityHistoryQuery(
            variables: DriveEntityHistoryArguments(
              driveId: driveId,
              ownerAddress: ownerAddress,
              entityType: EntityTypeTag.drive,
              after: cursor,
            ),
          ),
        );

        final data = result.data;
        if (data == null) {
          return null;
        }

        final edges = data.transactions.edges;
        txs.addAll(
          edges.map((e) => e.node).where(
                (tx) => doesTagsContainValidArFSVersion(
                  tx.tags.map((t) => Tag(t.name, t.value)).toList(),
                ),
              ),
        );

        if (txs.length > maxDriveRevisionsRead || stopped()) {
          return null;
        }

        if (!data.transactions.pageInfo.hasNextPage || edges.isEmpty) {
          break;
        }
        cursor = edges.last.cursor;
      }
    } catch (e) {
      logger.w('Could not read the drive history of $driveId: $e');
      return null;
    }

    // A private drive's revision with no IV cannot be decrypted; sync skips
    // it without a request, and so does this.
    final readable = driveKey == null
        ? txs
        : txs.where((tx) => tx.getTag(EntityTag.cipherIv) != null).toList();

    final ordered = [...readable]..sort((a, b) {
        if (_isNewerDriveEntityTx(a, than: b)) return 1;
        if (_isNewerDriveEntityTx(b, than: a)) return -1;
        return 0;
      });

    final bodies = List<Uint8List?>.filled(ordered.length, null);
    var failed = false;
    await runPooled(
      concurrency: _configService.config.maxConcurrentDataFetches.clamp(1, 100),
      itemCount: ordered.length,
      task: (i) async {
        // One failure already decides the answer, so the rest are not read.
        if (failed || stopped()) {
          failed = true;
          return;
        }
        try {
          bodies[i] = await getEntityDataFromNetwork(txId: ordered[i].id);
        } catch (e) {
          failed = true;
          logger.w('Could not read drive revision ${ordered[i].id}: $e');
        }
      },
      onItemDone: null,
    );

    if (failed || bodies.contains(null)) {
      return null;
    }

    final revisions = <DriveEntity>[];
    for (var i = 0; i < ordered.length; i++) {
      try {
        final entity = await DriveEntity.fromTransaction(
          ordered[i],
          _crypto,
          bodies[i]!,
          driveKey,
        );
        if (entity.ownerAddress == ownerAddress) {
          revisions.add(entity);
        }
      } on EntityTransactionParseException {
        logger.w('Skipping drive revision ${ordered[i].id}: it does not parse');
      }
    }

    return revisions;
  }

  /// Gets the newest drive entity transaction for each of a user's drives.
  ///
  /// One transaction per Drive-Id, across every page. The query sorts
  /// `HEIGHT_DESC`, but the gateway orders the transactions inside one block
  /// however it likes, so taking the first one per drive could pick a rename
  /// over the hide that followed it in the same block - and bring a hidden
  /// drive back. See [_isNewerDriveEntityTx] for the rule.
  Future<List<TransactionCommonMixin>> getUniqueUserDriveEntityTxs(
    String userAddress, {
    int maxRetries = defaultMaxRetries,
  }) async {
    // Return cached result if available for the same address.
    // Auth flow (isExistingUser, _validateUser) and sync (updateUserDrives)
    // all call this for the same wallet. Cache is invalidated explicitly
    // via clearUserDriveTxsCache() after drive creation or sync completion.
    if (_cachedUserDriveTxs != null &&
        _cachedUserDriveTxsAddress == userAddress) {
      logger.d('Using cached UserDriveEntityTxs');
      return _cachedUserDriveTxs!;
    }

    // Insertion-ordered, and replacing a value keeps its key's place, so the
    // list comes out in the order each drive was first seen.
    final newestByDriveId = <String?, TransactionCommonMixin>{};

    // The other end of each drive's history, for its creation time. The
    // newest transaction alone gave a renamed drive the rename's date.
    final oldestByDriveId = <String, TransactionCommonMixin>{};
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
      _userDriveTxPages.add(userAddress);

      final queryEdges = userDriveEntitiesQuery.data!.transactions.edges;
      final filteredEdges = queryEdges.where(
        (element) => doesTagsContainValidArFSVersion(
          element.node.tags.map((e) => Tag(e.name, e.value)).toList(),
        ),
      );

      cursor = queryEdges.isNotEmpty ? queryEdges.last.cursor : '';

      for (final tx in filteredEdges.map((e) => e.node)) {
        final driveId = tx.getTag(EntityTag.driveId);
        final seen = newestByDriveId[driveId];
        if (seen == null || _isNewerDriveEntityTx(tx, than: seen)) {
          newestByDriveId[driveId] = tx;
        }

        // A transaction with no usable Unix-Time cannot date the drive, and
        // ranking it would hide the one that can.
        if (driveId != null && _commitTimeOrZero(tx) > 0) {
          final oldest = oldestByDriveId[driveId];
          if (oldest == null || _isNewerDriveEntityTx(oldest, than: tx)) {
            oldestByDriveId[driveId] = tx;
          }
        }
      }

      final hasNextPage =
          userDriveEntitiesQuery.data!.transactions.pageInfo.hasNextPage;
      if (!hasNextPage) {
        break;
      }
    }

    final drives = newestByDriveId.values.toList();

    final creationTimes = {
      for (final entry in oldestByDriveId.entries)
        entry.key:
            DateTime.fromMillisecondsSinceEpoch(_commitTimeOrZero(entry.value)),
    };

    // Cache the result — cleared by clearUserDriveTxsCache()
    _cachedUserDriveTxsAddress = userAddress;
    _cachedUserDriveTxs = drives;
    _cachedUserDriveCreationTimes = creationTimes;

    return drives;
  }

  /// When each of [userAddress]'s drives was created, keyed by drive id: the
  /// commit time of the oldest drive transaction with a usable Unix-Time
  /// that [getUniqueUserDriveEntityTxs] found for it.
  ///
  /// Read from that listing's cache only, never the network, so it cannot
  /// fail or cost a request. Empty when the listing is not cached for this
  /// address, for instance because a finished sync cleared it; a drive
  /// missing from the map keeps the creation date it has.
  Map<String, DateTime> cachedUserDriveCreationTimes(String userAddress) {
    if (_cachedUserDriveTxsAddress != userAddress) {
      return const {};
    }
    return _cachedUserDriveCreationTimes ?? const {};
  }

  /// Whether [tx] is a later revision of its drive than [than].
  ///
  /// A higher block wins, and a pending transaction, with no block yet, is
  /// above every mined one. Inside one block, the later `Unix-Time` wins: the
  /// same order sync applies in [createDriveEntityHistoryFromTransactions],
  /// so the drive list and a full sync settle on the same revision. A tie on
  /// both keeps [than], the one the gateway listed first.
  static bool _isNewerDriveEntityTx(
    TransactionCommonMixin tx, {
    required TransactionCommonMixin than,
  }) {
    final height = tx.block?.height;
    final otherHeight = than.block?.height;

    if (height != otherHeight) {
      if (height == null) return true;
      if (otherHeight == null) return false;
      return height > otherHeight;
    }

    return _commitTimeOrZero(tx) > _commitTimeOrZero(than);
  }

  /// A transaction's `Unix-Time` in milliseconds, or 0 when it has none, it
  /// does not parse, or it is outside what a [DateTime] can hold. A malformed
  /// tag loses a tie rather than throwing out of the drive list, which would
  /// fail discovery for every drive in the wallet, not just this one.
  static int _commitTimeOrZero(TransactionCommonMixin tx) {
    if (tx.getTag(EntityTag.unixTime) == null) return 0;
    try {
      return tx.getCommitTime().millisecondsSinceEpoch;
    } on FormatException {
      return 0;
    } on ArgumentError {
      // Not RangeError: the VM throws one for a value DateTime cannot hold,
      // but the web build throws a plain ArgumentError. RangeError is a
      // subclass, so this catches both.
      return 0;
    }
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

  /// The drive signature, read through the multi-gateway waterfall.
  ///
  /// This is the login path (`ArDriveAuth`), where one unreachable gateway
  /// must not cost someone their session. Sync reads the same signature
  /// through [getDriveSignatureForDriveOnSync] instead.
  Future<DriveSignatureEntity?> getDriveSignatureForDrive(
    Wallet wallet,
    String driveId,
  ) =>
      _getDriveSignature(wallet, driveId, forSync: false);

  /// The drive signature as **sync** reads it: the configured gateway only.
  ///
  /// Drive discovery needs this for every private drive whose key is not
  /// already in memory. Routing it through the waterfall would have put the
  /// fan-out back into the sync path by the side door, one drive at a time.
  Future<DriveSignatureEntity?> getDriveSignatureForDriveOnSync(
    Wallet wallet,
    String driveId,
  ) =>
      _getDriveSignature(wallet, driveId, forSync: true);

  Future<DriveSignatureEntity?> _getDriveSignature(
    Wallet wallet,
    String driveId, {
    required bool forSync,
  }) async {
    // Drive signatures are immutable on-chain — cache permanently once fetched
    if (_cachedDriveSignatures.containsKey(driveId)) {
      return _cachedDriveSignatures[driveId];
    }

    final driveSignatureTx = await getDriveSignatureTxForDrive(wallet, driveId);

    final driveSignatureData = driveSignatureTx != null
        ? await (forSync
            ? _gatewayFallback.fetchDataForSync(driveSignatureTx.id, client)
            : _gatewayFallback.fetchData(driveSignatureTx.id, client))
        : null;

    final driveSignature =
        driveSignatureTx != null && driveSignatureData != null
            ? DriveSignatureEntity.fromTransaction(
                driveSignatureTx, driveSignatureData.bodyBytes)
            : null;
    _cachedDriveSignatures[driveId] = driveSignature;
    return driveSignature;
  }

  /// Gets the unique drive entities for a particular user.
  ///
  /// Each private drive's key comes from [resolvePrivateDriveKey], given the
  /// drive's newest transaction and data. A drive it can't open is returned
  /// in [UserDriveDiscovery.lockedDrives] rather than dropped, unless the
  /// reason was a failed read, which drops it for this pass as before.
  Future<UserDriveDiscovery> getUniqueUserDriveEntities(
    Wallet wallet,
    String password, {
    required Future<DriveKeyAttempt> Function(
      TransactionCommonMixin driveTx,
      Uint8List data,
    ) resolvePrivateDriveKey,

    /// Called as each drive's metadata comes back, with how many have arrived
    /// and how many were listed. Fires once with `(0, total)` as soon as the
    /// listing is known, so a reader waiting on this learns the size of the
    /// job before any of it is done.
    void Function(int read, int found)? onDriveRead,

    /// Called as each private drive is unlocked, with how many have been done
    /// and how many there are. The work after the fetch is serial and, for a
    /// private drive, expensive - a signature read over the network, a key
    /// derivation against the wallet, then a decrypt - so a wallet with
    /// several of them sits on a finished fetch count for a long time with
    /// nothing said. Never fires when there are none.
    void Function(int unlocked, int total)? onDriveUnlocked,
  }) async {
    try {
      final userAddress = await wallet.getAddress();
      final driveTxs = await getUniqueUserDriveEntityTxs(userAddress);

      // Distinct drives, not transactions. `getUniqueUserDriveEntityTxs` now
      // returns one transaction per drive, but it used to dedupe per GQL page
      // only, and the count then read "43 of 137" for twelve drives. Counting
      // ids keeps the figure right whatever the list holds.
      final distinctDriveIds = <String>{};
      for (final tx in driveTxs) {
        final id = tx.getTag(EntityTag.driveId);
        if (id != null) distinctDriveIds.add(id);
      }

      final driveCount = distinctDriveIds.length;
      final readDriveIds = <String>{};

      onDriveRead?.call(0, driveCount);

      // Sync's drive-discovery phase, and its only caller is
      // `_SyncRepository.updateUserDrives`. It reads the configured gateway
      // only, like every other sync read: this fires once per drive
      // transaction, so leaving it on the waterfall meant a user with a dozen
      // drives opened a dozen fan-outs to GAR gateways on every sync - which
      // is exactly the cost this change exists to remove.
      //
      // A drive whose metadata cannot be read is dropped from this pass, as
      // before; the full sync below re-reads it.
      // Bounded, not an unbounded `Future.wait` over every drive transaction.
      // Now that this reads one gateway instead of fanning out across
      // several, an unbounded burst is all aimed at that single host - and a
      // user with many drives would open every connection at once. Same limit
      // the metadata reads use.
      final driveResponses = List<Response?>.filled(driveTxs.length, null);

      await runPooled(
        concurrency:
            _configService.config.maxConcurrentDataFetches.clamp(1, 100),
        itemCount: driveTxs.length,
        task: (i) async {
          try {
            driveResponses[i] =
                await _gatewayFallback.fetchDataForSync(driveTxs[i].id, client);
          } catch (_) {
            // A drive we cannot read is dropped from this pass, as before.
          }

          // Counted per drive id, so the figure stays a count of drives even
          // if an id ever appears twice in the list.
          final id = driveTxs[i].getTag(EntityTag.driveId);
          if (id != null && readDriveIds.add(id)) {
            onDriveRead?.call(readDriveIds.length, driveCount);
          }
        },
        onItemDone: null,
      );

      // Cache raw bytes for reuse by getLatestDriveEntityWithId (e.g., during
      // password validation in _validateUser, which re-parses the same data)
      for (var i = 0; i < driveTxs.length; i++) {
        if (driveResponses[i] != null) {
          _cachedEntityDataBytes[driveTxs[i].id] = driveResponses[i]!.bodyBytes;
        }
      }

      final drivesById = <String?, DriveEntity>{};
      final drivesWithKey = <DriveEntity, DriveKey?>{};

      /// Drives whose newest transaction was reached but could not be used.
      ///
      /// `getUniqueUserDriveEntityTxs` returns only the newest transaction per
      /// drive, so this guards the invariant rather than a case it produces:
      /// if a drive's id ever appears twice, skipping the newest without
      /// recording it would let an older revision take its place and write
      /// stale metadata - worse than the drive simply being late.
      final handledDriveIds = <String?>{};

      // Distinct private drives, which is what the loop below will actually
      // unlock - counted by id rather than by row, for the same reason as the
      // read count above.
      final privateDriveIds = <String>{};
      for (final tx in driveTxs) {
        if (tx.getTag(EntityTag.drivePrivacy) == DrivePrivacyTag.private) {
          final id = tx.getTag(EntityTag.driveId);
          if (id != null) privateDriveIds.add(id);
        }
      }

      final unlockedDriveIds = <String>{};

      if (privateDriveIds.isNotEmpty) {
        onDriveUnlocked?.call(0, privateDriveIds.length);
      }

      final lockedDrives = <LockedDrive>[];

      for (var i = 0; i < driveTxs.length; i++) {
        if (driveResponses[i] == null) continue;
        final driveTx = driveTxs[i];

        // Skip a drive already handled. The list holds one transaction per
        // drive, so this guards that invariant; see [handledDriveIds].
        final txDriveId = driveTx.getTag(EntityTag.driveId);

        if (drivesById.containsKey(txDriveId) ||
            handledDriveIds.contains(txDriveId)) {
          continue;
        }

        if (driveTx.getTag(EntityTag.drivePrivacy) == DrivePrivacyTag.private) {
          // Contained per drive. A gateway hiccup on one drive's signature, or
          // a cancelled wallet prompt for it, used to throw out of drive
          // discovery and fail the entire sync before any drive had synced.
          // Now one drive's trouble is that drive's alone.
          DriveKeyAttempt attempt;
          try {
            attempt = await resolvePrivateDriveKey(
              driveTx,
              driveResponses[i]!.bodyBytes,
            );
          } catch (e) {
            logger.w('Could not open $txDriveId this pass: $e');
            attempt =
                const DriveKeyAttempt.failed(DriveUnlockFailure.unavailable);
          }

          // Claim the id, so that if it ever appeared twice an older
          // transaction could not quietly stand in for the newest one. See
          // [handledDriveIds].
          handledDriveIds.add(txDriveId);

          // Settled, however it settles. Counting only the drives whose keys
          // were derived here left the figure short of its total whenever a
          // signature could not be read.
          if (unlockedDriveIds.add(txDriveId!)) {
            onDriveUnlocked?.call(
              unlockedDriveIds.length,
              privateDriveIds.length,
            );
          }

          switch (PrivateDriveVerdict.of(attempt)) {
            case PrivateDriveVerdict.readable:
              drivesById[txDriveId] = attempt.entity!;
              drivesWithKey[attempt.entity!] = attempt.key;
            case PrivateDriveVerdict.skipped:
              // Not locked, just unread: dropped for this pass, as before, and
              // picked up on the next.
              logger
                  .w('Skipping $txDriveId for this pass: it could not be read');
            case PrivateDriveVerdict.locked:
              // The session has no key that opens it. It used to vanish here;
              // now it is listed as locked, with no name and no row.
              lockedDrives.add(
                LockedDrive(
                  driveId: txDriveId,
                  ownerAddress: driveTx.owner.address,
                  signatureType: DriveSignatureType.fromString(
                      driveTx.getTag(EntityTag.signatureType) ?? '1'),
                  lastUpdated: driveTx.getCommitTime(),
                ),
              );
          }

          continue;
        }

        try {
          final drive = await DriveEntity.fromTransaction(
            driveTx,
            _crypto,
            driveResponses[i]!.bodyBytes,
          );

          drivesById[drive.id] = drive;
          drivesWithKey[drive] = null;

          // If there's an error parsing the drive entity, just ignore it.
        } on EntityTransactionParseException catch (parseException) {
          logger.e(
            'Failed to parse transaction '
            'with id ${parseException.transactionId}',
            parseException,
          );
        }
      }
      return UserDriveDiscovery(
        drives: drivesWithKey,
        lockedDrives: lockedDrives,
      );
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
  /// Reads the drive entity for [driveId].
  ///
  /// [configuredGatewayOnly] picks which read policy the data fetch uses.
  /// Leave it false for a single read a user is waiting on and can retry -
  /// attaching a drive by id - where breadth wins and the full waterfall is
  /// worth its cost.
  ///
  /// Pass it for reads on the login and drive-discovery path. Those look like
  /// user-initiated reads and behave like sync: they run at startup, several
  /// at a time, with the user watching a spinner. The waterfall is the wrong
  /// trade there - it walks up to four gateways serially and asks
  /// `ArioSDK.getGateways()` for the list, which costs a Solana RPC on the
  /// startup path. See [DataGatewayFallback.fetchDataForSync].
  Future<DriveEntity?> getLatestDriveEntityWithId(
    String driveId, {
    String? driveOwner,
    SecretKey? driveKey,
    int maxRetries = defaultMaxRetries,
    bool configuredGatewayOnly = false,
  }) async {
    driveOwner ??= await getOwnerForDriveEntityWithId(driveId);

    if (driveOwner == null) {
      return null;
    }

    final fileTx = await getLatestDriveTx(
      driveId,
      driveOwner,
      maxRetries: maxRetries,
    );

    if (fileTx == null) {
      return null;
    }

    final entityBytes = await getEntityDataBytes(
      fileTx.id,
      configuredGatewayOnly: configuredGatewayOnly,
    );

    try {
      return await DriveEntity.fromTransaction(
          fileTx, _crypto, entityBytes, driveKey);
    } on EntityTransactionParseException catch (parseException) {
      logger.e(
        'Failed to parse transaction '
        'with id ${parseException.transactionId}',
        parseException,
      );
      return null;
    }
  }

  /// The newest valid metadata transaction of [driveId] by [driveOwner], or
  /// null when it has none. Its data is read by [getEntityDataBytes].
  ///
  /// The query half of [getLatestDriveEntityWithId], for a reader that has to
  /// tell a wrong key from a failed read - unlocking a drive does - and so
  /// decrypts the bytes itself.
  Future<TransactionCommonMixin?> getLatestDriveTx(
    String driveId,
    String driveOwner, {
    int maxRetries = defaultMaxRetries,
  }) async {
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

      return filteredEdges.first.node;
    }
  }

  /// The data of the entity transaction [txId], from the bytes drive
  /// discovery already read when it has them.
  ///
  /// [configuredGatewayOnly] as for [getLatestDriveEntityWithId]. Throws when
  /// the data can't be read.
  Future<Uint8List> getEntityDataBytes(
    String txId, {
    bool configuredGatewayOnly = false,
  }) async {
    // Use cached bytes if available (e.g., from getUniqueUserDriveEntities)
    final cachedBytes = _cachedEntityDataBytes[txId];

    if (cachedBytes != null) {
      return cachedBytes;
    }

    return (await (configuredGatewayOnly
            ? _gatewayFallback.fetchDataForSync(txId, client)
            : _gatewayFallback.fetchData(txId, client)))
        .bodyBytes;
  }

  /// Gets the drive privacy of the latest drive entity with the provided id.
  ///
  /// This function first checks for the owner of the first instance of the [DriveEntity]
  /// with the specified id and then queries for the latest instance of the [DriveEntity]
  /// by that owner.
  ///
  /// Returns `null` if no valid drive is found.
  /// Gets drive privacy and the owner address + latest transaction node.
  ///
  /// Returns both so the caller can reuse the owner and transaction node
  /// without making redundant GraphQL queries.
  Future<DrivePrivacyResult?> getDrivePrivacyForId(String driveId) async {
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

    return DrivePrivacyResult(
      privacy: driveTx.getTag(EntityTag.drivePrivacy),
      ownerAddress: driveOwner,
      driveTx: driveTx,
    );
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
      final allEdges = allFileEntitiesQuery.data!.transactions.edges;

      if (allEdges.isEmpty) {
        break;
      }

      final List<
              AllFileEntitiesWithId$Query$TransactionConnection$TransactionEdge>
          queryEdges = allEdges
              .where(
                (element) => doesTagsContainValidArFSVersion(
                  element.node.tags.map((e) => Tag(e.name, e.value)).toList(),
                ),
              )
              .toList();

      // A page with nothing usable on it is not the end of the history.
      //
      // This used to `break`, which is the difference between this walk and
      // [getLatestFileEntityWithId] - and the reason a file could report "no
      // other versions" while the newest-first query found it immediately.
      // This one sorts HEIGHT_ASC, so the first page it sees is the file's
      // *oldest* transactions, which are the ones most likely to predate the
      // ArFS version tag this filter requires. Stopping there discarded every
      // later page, and the caller reads an empty result as a failure.
      if (queryEdges.isEmpty) {
        cursor = allEdges.last.cursor;

        if (!allFileEntitiesQuery.data!.transactions.pageInfo.hasNextPage) {
          break;
        }

        continue;
      }
      for (var edge in queryEdges) {
        final fileTx = edge.node;
        final fileDataRes = await _gatewayFallback.fetchData(fileTx.id, client);

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
  /// [ownersByTxId] maps a transaction id to the owner it should be scoped by
  /// (the owner of the drive the tx belongs to). It takes precedence over
  /// [owner] per tx, letting a batch spanning multiple drives — e.g. the user's
  /// own drives plus attached drives owned by others — be scoped correctly
  /// instead of assuming a single owner. A tx present in neither [ownersByTxId]
  /// nor [owner] is left unresolved rather than queried unscoped.
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
    Map<String, String>? ownersByTxId,
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
      const chunkSize = maxGraphQLIdsPerQuery;
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

      // A pool, not a chunked `Future.wait`. Batching these meant each batch
      // waited for its slowest query before the next started, so one slow
      // chunk left the other workers idle - the same barrier that cost the
      // metadata reads above, on the confirmation queries this time.
      try {
        await runPooled(
          concurrency: maxConcurrent,
          itemCount: chunkStarts.length,
          task: (i) => queryChunk(chunkStarts[i]),
        );
      } catch (e) {
        logger.e('Error getting transactions confirmations on exception', e);
        rethrow;
      }
    }

    // The owner a tx should be scoped by: its per-tx owner if known, else the
    // single [owner]. Returns null when neither is available (unscopable).
    String? primaryOwnerFor(String? id) {
      if (id != null && ownersByTxId != null) {
        final mapped = ownersByTxId[id];
        if (mapped != null) return mapped;
      }
      return owner;
    }

    // First pass: scope each tx by its resolved owner and query each owner
    // once. This keeps every query selective even when the batch spans drives
    // with different owners. A tx with no resolvable owner is left unresolved
    // rather than queried unscoped, which would reintroduce the expensive scan.
    final idsByPrimaryOwner = <String, List<String?>>{};
    for (final id in transactionIds) {
      final resolvedOwner = primaryOwnerFor(id);
      if (resolvedOwner == null) {
        // No owner to scope by, so this tx is never queried. Drop it from the
        // result rather than leaving the pre-seeded -1, which the caller would
        // read as a real "not found" and could age an old pending tx into
        // failed. Absent => the caller skips it; it stays pending until its
        // drive/owner is known and it can be scoped on a later sync.
        transactionConfirmations.remove(id);
        continue;
      }
      idsByPrimaryOwner.putIfAbsent(resolvedOwner, () => []).add(id);
    }
    for (final entry in idsByPrimaryOwner.entries) {
      await queryConfirmations(entry.value, owner: entry.key);
    }

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
    if (ownerOverrides != null && ownerOverrides.isNotEmpty) {
      final idsByOverrideOwner = <String, List<String?>>{};
      for (final entry in transactionConfirmations.entries) {
        if (entry.value >= 0) continue;
        final txId = entry.key;
        final overrideOwner = ownerOverrides[txId];
        if (overrideOwner == null) continue;
        // Skip if the tx's first-pass owner already matched its override owner.
        if (overrideOwner == primaryOwnerFor(txId)) continue;
        idsByOverrideOwner.putIfAbsent(overrideOwner, () => []).add(txId);
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

  /// Which filter this gateway honours for leaving out bundled data items.
  /// See [UnbundledFilter].
  final _unbundledFilter = UnbundledFilter();

  /// One page of the AR [owner] paid to upload with ArDrive directly: its own
  /// mined transactions - not data items in bundles - from [minHeight] up,
  /// oldest first.
  ///
  /// Leaving out data items is what makes this cheap: an upload through
  /// Turbo is a data item in Turbo's bundle, which Turbo paid for, so a
  /// wallet that only ever used Turbo has nothing here at all. How to ask a
  /// gateway for that is not the same everywhere - see [UnbundledFilter].
  ///
  /// Filtered by owner alone on the gateway, and to ArDrive's own here: a tag
  /// filter on top made the ardrive.net indexer read 40 million rows and
  /// refuse. Every transaction still moves the page on, so another app's
  /// uploads are skipped, not read again.
  Future<ArFeePage> getArDriveFeesPage({
    required String owner,
    required int minHeight,
    KnownTxLookup? knownAmong,
    String? after,
  }) =>
      fetchDirectFeesPage(
        filter: _unbundledFilter,
        firstPage: after == null,
        fetch: (bundledIn) => _arDriveFeesPage(
          owner: owner,
          minHeight: minHeight,
          after: after,
          bundledIn: bundledIn,
          knownAmong: knownAmong,
        ),
      );

  Future<RawFeePage> _arDriveFeesPage({
    required String owner,
    required int minHeight,
    required String? after,
    required List<String>? bundledIn,
    required KnownTxLookup? knownAmong,
  }) async {
    final query = await graphQLRetry.execute(
      WalletArDriveFeesQuery(
        variables: WalletArDriveFeesArguments(
          owner: owner,
          minHeight: minHeight,
          bundledIn: bundledIn,
          after: after,
        ),
      ),
    );

    final transactions = query.data?.transactions;

    if (transactions == null) {
      throw ArweaveServiceException(
        'The query `WalletArDriveFeesQuery` returned no data',
      );
    }

    final tagsById = {
      for (final edge in transactions.edges)
        edge.node.id: {for (final tag in edge.node.tags) tag.name: tag.value},
    };

    // Only what the tags leave open is asked of the database, and only when
    // there is any: for ArDrive's own uploads the tags settle it.
    final known = await lookUpKnown(knownAmong, {
      for (final edge in transactions.edges)
        if (edge.node.bundledIn == null &&
            !isArDriveByTags(tagsById[edge.node.id]!))
          edge.node.id,
    });

    var winston = BigInt.zero;
    var count = 0;
    var unbundled = 0;
    final excluded = <String, BigInt>{};
    int? lastHeight;

    for (final edge in transactions.edges) {
      lastHeight = edge.node.block?.height ?? lastHeight;

      // A data item in a bundle, from a gateway that would not leave them
      // out: free to the wallet, whatever its tags say.
      if (edge.node.bundledIn != null) {
        continue;
      }

      unbundled++;

      final tags = tagsById[edge.node.id]!;
      final isArDrive = isArDriveTransaction(
        txId: edge.node.id,
        tags: tags,
        knownTxIds: known,
      );

      final fee = arDrivePayment(
        feeWinston: edge.node.fee.winston,
        quantityWinston: edge.node.quantity.winston,
        tags: tags,
      );

      if (isArDrive) {
        winston += fee;
        count++;
      } else if (fee > BigInt.zero) {
        // Perhaps not yet synced: looked at again by the next count.
        excluded[edge.node.id] = fee;
      }
    }

    return RawFeePage(
      page: ArFeePage(
        winston: winston,
        count: count,
        lastHeight: lastHeight,
        cursor:
            transactions.edges.isEmpty ? after : transactions.edges.last.cursor,
        hasMore: transactions.pageInfo.hasNextPage,
        excluded: excluded,
      ),
      rows: transactions.edges.length,
      unbundledRows: unbundled,
    );
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
  }) async {
    await client.transactions.post(
      transaction,
      dryRun: dryRun,
    );

    if (!dryRun) {
      // Posted, so paid for: the permanence panel's figures have moved.
      PermanenceCache.shared.spendChanged();
    }
  }

  /// Uploads a transaction using the same chunked flow as file data uploads:
  /// header then chunks with [maxConcurrentUploadCount] (default 1) to avoid
  /// gateway 400s from data_root propagation when many chunk requests hit
  /// before the tx is indexed.
  ///
  /// [onTransactionPosted] fires once the transaction **header** has been
  /// accepted, before any chunk is sent. That ordering is
  /// `TransactionUploader`'s (arweave-dart v4.0.2): `upload()` awaits
  /// `_postTransactionHeader()` and only then yields its first event, so a
  /// caller that never sees the callback knows nothing reached the network,
  /// and one that does knows a transaction now exists and will be paid for
  /// whether or not its chunks follow. Without it a chunk failure and a
  /// refused header are the same exception, and a caller can only guess which
  /// of the two it is holding.
  Future<void> uploadTx(
    Transaction transaction, {
    int maxConcurrentUploadCount = 1,
    bool dryRun = false,
    void Function()? onTransactionPosted,
  }) =>
      drainUpload(
        client.transactions.upload(
          transaction,
          maxConcurrentUploadCount: maxConcurrentUploadCount,
          dryRun: dryRun,
        ),
        dryRun: dryRun,
        onTransactionPosted: () {
          if (!dryRun) {
            PermanenceCache.shared.spendChanged();
          }

          onTransactionPosted?.call();
        },
      );

  /// Drains an upload's event stream, reporting the header post the first time
  /// the stream says anything.
  ///
  /// Separate from [uploadTx], and typed on `Object?` rather than on the
  /// uploader, because `ArweaveTransactionsApi` is not exported by
  /// `package:arweave` and so cannot be named - or mocked - from here. This is
  /// the whole rule, and it is the part that can be got wrong: firing eagerly
  /// would invent a charge that never happened, and firing on every event
  /// would report one transaction many times.
  @visibleForTesting
  static Future<void> drainUpload(
    Stream<Object?> events, {
    required bool dryRun,
    void Function()? onTransactionPosted,
  }) async {
    var posted = false;

    await for (final _ in events) {
      // A dry run yields the uploader without posting anything, so it must not
      // be reported as a transaction that exists.
      if (posted || dryRun) continue;
      posted = true;
      onTransactionPosted?.call();
    }
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

  /// The size and content type of each data transaction, in batches.
  ///
  /// Every batch yielded has a key for every id in it. A value is `null` only
  /// when neither source below could say anything about that id, so a caller
  /// can report the file as failed rather than lose it without a word.
  ///
  /// GraphQL is asked first, because one query answers a whole batch. An id it
  /// does not answer for - its batch failed, or the index simply did not
  /// return it - is asked of the data gateway with a HEAD on `/raw/{id}`,
  /// which carries the transaction's exact size and its `Content-Type` tag.
  ///
  /// That second source is not a nicety. The query here filters by id alone,
  /// and a gateway's index can refuse it outright for reading too many rows
  /// (#2222), for every batch, deterministically. Before the HEAD, such a
  /// batch was logged and skipped, so an import of a manifest found nothing to
  /// import and could not say which files, or why.
  Stream<Map<String, DataTxSizeAndType?>> getSizeAndTypeOfDataTxs(
    List<String> transactionIds, {
    int batchSize = 5,
  }) async* {
    for (var i = 0; i < transactionIds.length; i += batchSize) {
      final end = (i + batchSize < transactionIds.length)
          ? i + batchSize
          : transactionIds.length;
      final batch = transactionIds.sublist(i, end);

      logger.i('Fetching size and type for batch of ${batch.length}');

      final results = <String, DataTxSizeAndType?>{};

      try {
        final query = await graphQLRetry.execute(
          InfoOfTransactionsToBePinnedQuery(
            variables: InfoOfTransactionsToBePinnedArguments(
              transactionIds: batch,
            ),
          ),
        );

        final edges = query.data?.transactions.edges ??
            const <InfoOfTransactionsToBePinned$Query$TransactionConnection$TransactionEdge>[];

        for (final edge in edges) {
          final tx = edge.node;
          final size = int.tryParse(tx.data.size);
          if (size == null) continue;

          results[tx.id] = DataTxSizeAndType(
            size: size,
            contentType: tx.tags
                .firstWhereOrNull((tag) => tag.name == 'Content-Type')
                ?.value,
          );
        }
      } catch (e) {
        logger.w('GraphQL could not describe a batch, asking the gateway: $e');
      }

      final unanswered = batch.where((id) => !results.containsKey(id));
      final fromGateway = await Future.wait(
        unanswered.map((id) async => MapEntry(id, await _headDataTx(id))),
      );
      results.addEntries(fromGateway);

      yield results;
    }
  }

  /// The size and content type of [txId] from the data gateway's headers, or
  /// `null` when the gateway does not answer with both a 200 and a length.
  Future<DataTxSizeAndType?> _headDataTx(String txId) async {
    final gateway = _configService.config.arweaveGatewayForDataRequest.url;
    final uri = Uri.parse('$gateway/raw/$txId');
    try {
      final response = await retry(
        () async {
          final response =
              await _httpClient.head(uri).timeout(const Duration(seconds: 15));

          // `retry` retries only what throws, and an answer is not a throw. A
          // busy or unwell gateway has to be one, or the second attempt is
          // never spent on the very answers it exists for. A 404 is left as
          // an answer: asking again will not make the data exist.
          if (_isTransientStatus(response.statusCode)) {
            throw _TransientHeadStatus(response.statusCode);
          }

          return response;
        },
        maxAttempts: 2,
      );

      if (response.statusCode != 200) {
        logger.w('HEAD for $txId answered ${response.statusCode}');
        return null;
      }

      final size = int.tryParse(response.headers['content-length'] ?? '');
      if (size == null) return null;

      return DataTxSizeAndType(
        size: size,
        // Mime only, without parameters such as charset.
        contentType:
            response.headers['content-type']?.replaceFirst(RegExp(r';.*$'), ''),
      );
    } catch (e) {
      logger.w('HEAD for $txId failed: $e');
      return null;
    }
  }
}

/// A status worth asking the gateway again for: it timed the request out, is
/// rate limiting, or is unwell.
bool _isTransientStatus(int status) =>
    status == 408 || status == 429 || status >= 500;

class _TransientHeadStatus implements Exception {
  final int statusCode;

  const _TransientHeadStatus(this.statusCode);

  @override
  String toString() => 'Gateway answered $statusCode';
}

/// What a file entity needs from its data transaction.
class DataTxSizeAndType {
  final int size;

  /// The `Content-Type` tag, when the transaction has one.
  final String? contentType;

  const DataTxSizeAndType({required this.size, this.contentType});
}

/// The entity history of a particular drive, chunked by block height.
class DriveEntityHistory {
  final int? lastBlockHeight;

  /// A list of block entities, ordered by ascending block height.
  final List<BlockEntities> blockHistory;

  /// Transactions whose metadata could not be read, and which were therefore
  /// left out of [blockHistory]. Surfaced so the sync layer can count and
  /// report them rather than dropping them silently.
  final List<String> skippedTxIds;

  DriveEntityHistory(
    this.lastBlockHeight,
    this.blockHistory, {
    this.skippedTxIds = const [],
  });
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

/// Result of [ArweaveService.getDrivePrivacyForId], containing the privacy tag
/// plus the owner and transaction node to avoid redundant re-queries.
class DrivePrivacyResult {
  final String? privacy;
  final String ownerAddress;
  final TransactionCommonMixin driveTx;

  DrivePrivacyResult({
    required this.privacy,
    required this.ownerAddress,
    required this.driveTx,
  });
}

class TransactionNotFound implements Exception {
  final String txId;

  TransactionNotFound(this.txId);
}
