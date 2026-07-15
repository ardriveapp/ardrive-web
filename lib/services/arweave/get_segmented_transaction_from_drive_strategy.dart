import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/sync/domain/models/drive_entity_history.dart';
import 'package:ardrive/utils/arfs_txs_filter.dart';
import 'package:ardrive/utils/exceptions.dart';
import 'package:ardrive/utils/graphql_retry.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/snapshots/snapshot_item_to_be_created.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:collection/collection.dart';

/// Strategy to get the transactions from the drive
abstract class GetSegmentedTransactionFromDriveStrategy {
  Stream<List<DriveEntityHistoryTransactionModel>>
      getSegmentedTransactionFromDrive(
    String driveId, {
    required String ownerAddress,
    int? minBlockHeight,
    int? maxBlockHeight,
  });
}

/// Page size used on the fallback GraphQL endpoint and as the safe
/// downshift size. Goldsky (the fallback) caps pages at 100 and, when asked
/// for more, silently clamps to 100 while falsely reporting
/// `hasNextPage: false` — so requests above 100 must never reach it.
const kFallbackGqlPageSize = 100;

/// Attempts per page while probing the primary endpoint at a page size
/// above the safe fallback size. Failures there are usually deterministic
/// (indexer scan limits), so retrying many times only delays the downshift.
const _oversizedPhaseMaxAttempts = 2;

/// Attempts per page on the primary endpoint at the safe page size. Failures
/// at <=100 are overwhelmingly transient (network blips, brief gateway
/// hiccups), so this matches the pre-ladder retry budget: a short outage is
/// ridden out with backoff instead of failing over to the fallback index.
const _standardPhaseMaxAttempts = 8;

/// Smallest page size any known gateway clamps to. A final page smaller than
/// this cannot be a silent clamp (gateways clamp to their page-size limit,
/// e.g. 100 on Goldsky or 10 on some forks — never below), so it needs no
/// verification page. Keeps warm syncs of small drives at one request.
const _minPlausibleClampSize = 10;

/// Gets the transactions from the drive, without any `Entity-Type` filtering,
/// returning all the transactions ordered by block height.
///
/// Pagination is endpoint-sticky and runs as a three-phase ladder:
///   A. primary endpoint at [pageSize] (large pages, fast path)
///   B. primary endpoint at [kFallbackGqlPageSize] (rules out failures
///      specific to large pages, e.g. indexer row-scan limits)
///   C. fallback endpoint at [kFallbackGqlPageSize]
/// A phase restarts the range from the beginning; [_seen-id] deduplication
/// makes the restart safe for consumers. Cursors are never reused across
/// endpoints (they are gateway-specific opaque values), and the fallback is
/// never asked for more than 100 items per page.
///
/// Owners recorded in [ownersPreferringFallback] skip phases A/B for the
/// rest of the session, so a wallet whose data the primary indexer cannot
/// serve pays the probing cost once instead of once per drive.
class GetSegmentedTransactionFromDriveWithoutEntityTypeFilterStrategy
    implements GetSegmentedTransactionFromDriveStrategy {
  final GraphQLRetry _graphQLRetry;
  final int pageSize;
  final Set<String> ownersPreferringFallback;

  GetSegmentedTransactionFromDriveWithoutEntityTypeFilterStrategy(
    this._graphQLRetry, {
    this.pageSize = kFallbackGqlPageSize,
    Set<String>? ownersPreferringFallback,
  }) : ownersPreferringFallback = ownersPreferringFallback ?? <String>{};

  @override
  Stream<List<DriveEntityHistoryTransactionModel>>
      getSegmentedTransactionFromDrive(
    String driveId, {
    required String ownerAddress,
    int? minBlockHeight,
    int? maxBlockHeight,
  }) async* {
    final seenTxIds = <String>{};

    if (!ownersPreferringFallback.contains(ownerAddress)) {
      // Phase A: primary endpoint at the configured page size.
      // NOTE: phases re-yield via await-for instead of yield*: errors from a
      // yield*'d stream are forwarded to the listener as stream events and
      // BYPASS a surrounding try/catch, which would defeat the ladder.
      try {
        await for (final batch in _paginate(
          driveId: driveId,
          ownerAddress: ownerAddress,
          minBlockHeight: minBlockHeight,
          maxBlockHeight: maxBlockHeight,
          pageSize: pageSize,
          useFallbackEndpoint: false,
          maxAttempts: pageSize > kFallbackGqlPageSize
              ? _oversizedPhaseMaxAttempts
              : _standardPhaseMaxAttempts,
          seenTxIds: seenTxIds,
        )) {
          yield batch;
        }
        return;
      } on NoConnectionException {
        rethrow; // offline: every endpoint fails; don't ladder or mark owner
      } catch (e) {
        logger.w('Drive history pagination failed on primary endpoint at '
            'page size $pageSize for drive $driveId: $e');
      }

      // Phase B: primary endpoint at the safe page size (only meaningful
      // when phase A used a larger one).
      if (pageSize > kFallbackGqlPageSize) {
        try {
          await for (final batch in _paginate(
            driveId: driveId,
            ownerAddress: ownerAddress,
            minBlockHeight: minBlockHeight,
            maxBlockHeight: maxBlockHeight,
            pageSize: kFallbackGqlPageSize,
            useFallbackEndpoint: false,
            maxAttempts: _standardPhaseMaxAttempts,
            seenTxIds: seenTxIds,
          )) {
            yield batch;
          }
          return;
        } on NoConnectionException {
          rethrow;
        } catch (e) {
          logger.w('Drive history pagination failed on primary endpoint at '
              'page size $kFallbackGqlPageSize for drive $driveId: $e');
        }
      }

      logger.w('Primary GraphQL endpoint cannot serve drive history for '
          'owner $ownerAddress; using fallback for the rest of this session');
      ownersPreferringFallback.add(ownerAddress);
    }

    // Phase C: fallback endpoint at the safe page size. Errors here
    // propagate: the drive is reported failed through the existing sync
    // error flow instead of being silently truncated.
    yield* _paginate(
      driveId: driveId,
      ownerAddress: ownerAddress,
      minBlockHeight: minBlockHeight,
      maxBlockHeight: maxBlockHeight,
      pageSize: kFallbackGqlPageSize,
      useFallbackEndpoint: true,
      maxAttempts: 3,
      seenTxIds: seenTxIds,
    );
  }

  Stream<List<DriveEntityHistoryTransactionModel>> _paginate({
    required String driveId,
    required String ownerAddress,
    int? minBlockHeight,
    int? maxBlockHeight,
    required int pageSize,
    required bool useFallbackEndpoint,
    required int maxAttempts,
    required Set<String> seenTxIds,
  }) async* {
    String? cursor;
    var effectivePageSize = pageSize;

    while (true) {
      final queryResult = await _graphQLRetry.execute(
        DriveEntityHistoryWithoutEntityTypeFilterQuery(
          variables: DriveEntityHistoryWithoutEntityTypeFilterArguments(
            driveId: driveId,
            minBlockHeight: minBlockHeight,
            maxBlockHeight: maxBlockHeight,
            after: cursor,
            ownerAddress: ownerAddress,
            pageSize: effectivePageSize,
          ),
        ),
        maxAttempts: maxAttempts,
        allowFallback: false,
        useFallbackEndpoint: useFallbackEndpoint,
      );

      if (queryResult.data == null) {
        // A null-data response with no errors must not look like a completed
        // range: downstream, stream completion is treated as proof of
        // completeness (sync watermarks, created snapshots). Throw so the
        // ladder retries or the drive fails visibly.
        throw GraphQLException(
            'Null data with no errors while paginating drive history');
      }

      final rawEdges = queryResult.data!.transactions.edges;

      final transactions = rawEdges
          .where((e) => !seenTxIds.contains(e.node.id))
          .where((e) => _isSupportedArFSVersion(e.node))
          .map((e) => DriveEntityHistoryTransactionModel(
              transactionCommonMixin: e.node, cursor: e.cursor))
          .toList();

      for (final t in transactions) {
        seenTxIds.add(t.transactionCommonMixin.id);
      }

      yield transactions;

      var hasNextPage = queryResult.data!.transactions.pageInfo.hasNextPage;

      // Clamp guard: we asked for more than 100 but received exactly a
      // fallback-sized page with `hasNextPage: false`. Some gateways clamp
      // silently AND misreport hasNextPage, which would truncate the drive.
      // Downshift and fetch one verification page (same endpoint, so the
      // cursor stays valid); a genuinely finished range just returns an
      // empty page next.
      if (!hasNextPage &&
          effectivePageSize > kFallbackGqlPageSize &&
          rawEdges.length >= _minPlausibleClampSize) {
        // A full-looking final page of an oversized request may be a silent
        // clamp (Goldsky: 100; some forks: 10) with a false hasNextPage, so
        // it gets one verification page. Tails smaller than any plausible
        // clamp size are genuine and skip the extra request.
        logger.d('Verifying end of range (requested $effectivePageSize, '
            'received ${rawEdges.length}, hasNextPage false)');
        effectivePageSize = kFallbackGqlPageSize;
        hasNextPage = true;
      }

      // Advance the cursor from the last RAW edge. Advancing from the
      // filtered list would reset the cursor to null (restarting the range)
      // whenever a page contains only unsupported-ArFS transactions.
      if (rawEdges.isNotEmpty) {
        cursor = rawEdges.last.cursor;
      }

      if (!hasNextPage) {
        break;
      }

      if (rawEdges.isEmpty) {
        // hasNextPage=true with an empty page means the gateway is
        // misbehaving. Completing the stream here would be treated as a
        // fully-synced range downstream (and could bake a truncated snapshot
        // on-chain), so fail the phase instead: the ladder retries on the
        // next endpoint, and a phase-C failure surfaces as a failed drive.
        throw GraphQLException(
            'Empty page with hasNextPage=true for drive $driveId');
      }
    }
  }
}

/// Gets the transactions from the drive, filtering by `Entity-Type` tag.
///
/// This strategy is used to get the transactions for the `Folder` and `File` entities.
/// It first gets the transactions for the `Folder` entity, and then for the `File` entity.
class GetSegmentedTransactionFromDriveFilteringByEntityTypeStrategy
    implements GetSegmentedTransactionFromDriveStrategy {
  final GraphQLRetry _graphQLRetry;

  GetSegmentedTransactionFromDriveFilteringByEntityTypeStrategy(
    this._graphQLRetry,
  );

  @override
  Stream<List<DriveEntityHistoryTransactionModel>>
      getSegmentedTransactionFromDrive(
    String driveId, {
    required String ownerAddress,
    int? minBlockHeight,
    int? maxBlockHeight,
  }) async* {
    yield* _getSegmentedTransaction(
      driveId: driveId,
      entityType: EntityTypeTag.drive,
      ownerAddress: ownerAddress,
      minBlockHeight: minBlockHeight,
      maxBlockHeight: maxBlockHeight,
      graphQLRetry: _graphQLRetry,
    );
    yield* _getSegmentedTransaction(
      driveId: driveId,
      entityType: EntityTypeTag.folder,
      ownerAddress: ownerAddress,
      minBlockHeight: minBlockHeight,
      maxBlockHeight: maxBlockHeight,
      graphQLRetry: _graphQLRetry,
    );
    yield* _getSegmentedTransaction(
      driveId: driveId,
      entityType: EntityTypeTag.file,
      ownerAddress: ownerAddress,
      minBlockHeight: minBlockHeight,
      maxBlockHeight: maxBlockHeight,
      graphQLRetry: _graphQLRetry,
    );
  }

  Stream<List<DriveEntityHistoryTransactionModel>> _getSegmentedTransaction({
    required String driveId,
    required String entityType,
    required String ownerAddress,
    int? minBlockHeight,
    int? maxBlockHeight,
    required GraphQLRetry graphQLRetry,
  }) async* {
    String? cursor;
    while (true) {
      final queryResult = await graphQLRetry.execute(
        DriveEntityHistoryQuery(
          variables: DriveEntityHistoryArguments(
            driveId: driveId,
            minBlockHeight: minBlockHeight,
            maxBlockHeight: maxBlockHeight,
            after: cursor,
            ownerAddress: ownerAddress,
            entityType: entityType,
          ),
        ),
      );

      if (queryResult.data == null) {
        logger.w('No data in the query result');
        break;
      }

      final rawEdges = queryResult.data!.transactions.edges;

      final transactions = rawEdges
          .where((edge) => _isSupportedArFSVersion(edge.node))
          .map((e) => DriveEntityHistoryTransactionModel(
                transactionCommonMixin: e.node,
                cursor: e.cursor,
              ))
          .toList();

      yield transactions;

      // Advance from the last RAW edge so a page of unsupported-ArFS
      // transactions cannot reset the cursor and restart the range.
      cursor = rawEdges.isNotEmpty ? rawEdges.last.cursor : cursor;

      if (!queryResult.data!.transactions.pageInfo.hasNextPage) {
        break;
      }

      if (rawEdges.isEmpty) {
        logger.w('Empty page with hasNextPage=true for drive $driveId; '
            'stopping pagination');
        break;
      }
    }
  }
}

bool _isSupportedArFSVersion(TransactionCommonMixin node) {
  final arfsTag =
      node.tags.firstWhereOrNull((tag) => tag.name == EntityTag.arFs);
  return arfsTag != null && supportedArFSVersionsSet.contains(arfsTag.value);
}

DriveHistoryTransactionEdge parseDriveHistoryTransactionEdge(
  DriveHistoryWithoutEntityTypeFilterTransactionEdge edge,
) {
  return DriveHistoryTransactionEdge.fromJson({
    'cursor': edge.cursor,
    'node': edge.node.toJson(),
  });
}
