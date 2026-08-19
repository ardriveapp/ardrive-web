import 'package:ardrive/drive_state/domain/drive_state_outcome.dart';
import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/utils/graphql_retry.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Finding a drive's state artifacts.
///
/// `docs/DRIVE_STATE_ARTIFACT.md` §4.3 gives discovery an order: an ArNS name
/// first when the drive has one, GraphQL by `Entity-Type` + `Drive-Id` + owner
/// as the fallback, and nothing found otherwise. Decision D6 in
/// `docs/drive-state/DECISIONS.md` leaves ArNS out of v1 — the name is the
/// acceleration, not the mechanism — but says discovery must be built behind
/// an interface so it drops in later. That is what [DriveStateDiscovery] is
/// for: an ArNS resolver becomes a second implementation and no caller
/// changes.
///
/// Two properties of this layer are load-bearing:
///
///  * **It finds, it does not trust.** §4.2 is explicit that verification must
///    not live in the discovery path. A candidate here is a transaction id and
///    the tags an untrusted indexer reported for it; the signature, the
///    `Drive-Id` and the coverage tags decide whether to use it, elsewhere.
///  * **Transport is irrelevant.** §4.4 requires L1 transactions and bundled
///    data items to be read without preference, so nothing here filters on
///    `bundledIn`.

/// A transaction an indexer claims is a drive state artifact.
///
/// Nothing here has been verified. The tags are as reported; the getters parse
/// them leniently and return null rather than throwing, because a malformed
/// tag on a hostile or broken transaction must not be able to fail a sync.
@immutable
class DriveStateArtifactCandidate extends Equatable {
  DriveStateArtifactCandidate({
    required this.txId,
    required this.ownerAddress,
    required Map<String, String> tags,
    this.bundledInTxId,
    this.minedAtHeight,
    this.minedAtTimestamp,
  }) : tags = Map.unmodifiable(tags);

  /// The transaction id to fetch. Works over ordinary HTTP for both an L1
  /// transaction and a bundled data item (§4.4), which is why the bundle is
  /// recorded but never required.
  final String txId;

  /// The address the indexer attributes the transaction to. Kept so a caller
  /// can see what was matched; it is not proof of authorship — the payload
  /// signature is (§2.2, §4.4).
  final String ownerAddress;

  /// Set when the artifact was uploaded through a bundler. Informational: a
  /// bundled item is read exactly like an L1 transaction.
  final String? bundledInTxId;

  /// Null while the transaction is still pending.
  final int? minedAtHeight;
  final int? minedAtTimestamp;

  /// Every tag the indexer reported, unmodifiable. Kept whole because §6 says
  /// unknown tags are ignored, not rejected — a reader takes what it knows and
  /// a later version can read more without this class changing.
  final Map<String, String> tags;

  String? tag(String name) => tags[name];

  int? _intTag(String name) {
    final value = tags[name];
    return value == null ? null : int.tryParse(value);
  }

  String? get driveId => tags[EntityTag.driveId];
  String? get entityType => tags[EntityTag.entityType];
  String? get arFsVersion => tags[EntityTag.arFs];
  String? get driveStateId => tags[EntityTag.driveStateId];
  String? get stateVersion => tags[EntityTag.stateVersion];
  String? get contentEncoding => tags[EntityTag.contentEncoding];
  String? get cipher => tags[EntityTag.cipher];
  String? get cipherIv => tags[EntityTag.cipherIv];

  /// Always 0 for a v1 artifact — every artifact is a full copy (§3.4) — but
  /// read from the tag, not assumed, because the format does not forbid an
  /// incremental artifact and §5's range arithmetic already handles one.
  int? get blockStart => _intTag(EntityTag.blockStart);

  /// The maximum block height accounted for. This is what orders artifacts.
  int? get blockEnd => _intTag(EntityTag.blockEnd);

  /// The range where data was actually found, against [blockStart]/[blockEnd]
  /// which is the range searched. Lets a client know an artifact is empty
  /// without fetching it.
  int? get dataStart => _intTag(EntityTag.dataStart);
  int? get dataEnd => _intTag(EntityTag.dataEnd);

  int? get entityCount => _intTag(EntityTag.entityCount);
  int? get unixTime => _intTag(EntityTag.unixTime);

  bool get isBundled => bundledInTxId != null;

  @override
  List<Object?> get props => [
        txId,
        ownerAddress,
        bundledInTxId,
        minedAtHeight,
        minedAtTimestamp,
        tags,
      ];

  @override
  String toString() => 'DriveStateArtifactCandidate(tx=$txId, '
      'blockEnd=$blockEnd, entityCount=$entityCount, bundled=$isBundled)';
}

/// The result of asking for a drive's artifacts.
///
/// [discoveryFailed] is the reason this is a type and not a bare list. "The
/// indexer did not answer" and "this drive has no artifact" both yield no
/// candidates, and §7 forbids letting those look the same. A caller that only
/// ever saw an empty list would have to report
/// [DriveStateOutcome.noneFound] for a query that was never answered.
@immutable
class DriveStateDiscoveryResult extends Equatable {
  const DriveStateDiscoveryResult({
    required this.candidates,
    this.discoveryFailed = false,
  });

  const DriveStateDiscoveryResult.failed()
      : candidates = const [],
        discoveryFailed = true;

  const DriveStateDiscoveryResult.none()
      : candidates = const [],
        discoveryFailed = false;

  /// Newest first by `Block-End`. Never null, never throws — an empty list is
  /// the fallback, in both senses.
  final List<DriveStateArtifactCandidate> candidates;

  /// True when the lookup itself did not complete. The candidates, if any, are
  /// still usable: a paginated query that fails part-way keeps what it already
  /// found, exactly as the snapshot query does.
  final bool discoveryFailed;

  bool get isEmpty => candidates.isEmpty;

  DriveStateArtifactCandidate? get newest => candidates.firstOrNull;

  @override
  List<Object?> get props => [candidates, discoveryFailed];
}

/// Finds the drive state artifacts a drive owner published.
///
/// Implementations must not throw. Every failure is a fallback: a drive with
/// no discoverable artifact syncs from snapshots and GraphQL exactly as it
/// does today.
abstract class DriveStateDiscovery {
  Future<DriveStateDiscoveryResult> findCandidates({
    required String driveId,
    required String ownerAddress,
    int? minBlockHeight,
  });
}

/// Discovery by GraphQL — decision D6's v1 path, and the only path for drives
/// without a name, which is most of them.
class GraphQLDriveStateDiscovery implements DriveStateDiscovery {
  GraphQLDriveStateDiscovery({
    required GraphQLRetry graphQLRetry,
    DriveStateOutcomeReporter reporter = const DriveStateOutcomeReporter(),
    int maxPages = _defaultMaxPages,
  })  : _graphQLRetry = graphQLRetry,
        _reporter = reporter,
        _maxPages = maxPages;

  /// One page of 100, sorted `HEIGHT_DESC`, is the 100 most recently mined
  /// artifacts for the drive. An artifact mined before all of those cannot
  /// legitimately carry a higher `Block-End`, since a producer cannot account
  /// for blocks that did not exist when it was mined — so paging further would
  /// cost queries against the least reliable component in the stack (§4.1) to
  /// find candidates that are, by construction, already superseded. A caller
  /// that wants the full history can raise it.
  static const int _defaultMaxPages = 1;

  final GraphQLRetry _graphQLRetry;
  final DriveStateOutcomeReporter _reporter;
  final int _maxPages;

  @override
  Future<DriveStateDiscoveryResult> findCandidates({
    required String driveId,
    required String ownerAddress,
    int? minBlockHeight,
  }) async {
    final candidates = <DriveStateArtifactCandidate>[];
    var cursor = '';
    var pages = 0;
    var discarded = 0;

    while (pages < _maxPages) {
      final DriveStateEntityHistory$Query$TransactionConnection transactions;

      try {
        final response = await _graphQLRetry.execute(
          DriveStateEntityHistoryQuery(
            variables: DriveStateEntityHistoryArguments(
              driveIds: [driveId],
              after: cursor,
              minBlockHeight: minBlockHeight,
              ownerAddress: ownerAddress,
            ),
          ),
        );

        final data = response.data;
        if (data == null) {
          // A response with no data is the indexer declining to answer, not an
          // answer of "none". Reported as a failure so the caller does not log
          // this drive as having no artifact.
          _reporter.note(
            driveId: driveId,
            message: 'discovery query returned no data after $pages page(s); '
                'syncing without an artifact',
            level: DriveStateLogLevel.warning,
          );
          return DriveStateDiscoveryResult(
            candidates: _newestFirst(candidates),
            discoveryFailed: true,
          );
        }

        transactions = data.transactions;
      } catch (e) {
        // Never rethrow. Anything already found is kept - the query is
        // HEIGHT_DESC, so a part-way failure typically kept the newest, which
        // is the one that matters.
        _reporter.note(
          driveId: driveId,
          message: 'discovery query failed after $pages page(s) with '
              '${candidates.length} candidate(s) found; '
              'syncing without an artifact: $e',
          level: DriveStateLogLevel.warning,
        );
        return DriveStateDiscoveryResult(
          candidates: _newestFirst(candidates),
          discoveryFailed: true,
        );
      }

      pages++;
      final edges = transactions.edges;

      for (final edge in edges) {
        final candidate = _toCandidate(edge.node);
        if (_isUsable(candidate,
            driveId: driveId, ownerAddress: ownerAddress)) {
          candidates.add(candidate);
        } else {
          discarded++;
        }
      }

      // An empty page with hasNextPage=true would otherwise loop forever; the
      // snapshot query guards the same way, for the same indexer.
      if (edges.isEmpty) {
        break;
      }

      cursor = edges.last.cursor;

      if (!transactions.pageInfo.hasNextPage) {
        break;
      }
    }

    // What the index actually returned, before anything downstream decides
    // whether to trust it. Separates "the gateway did not tell us about the
    // artifact" from "we knew about it and could not use it" - two completely
    // different fixes.
    _reporter.note(
      driveId: driveId,
      message: 'discovery found ${candidates.length} candidate(s) across '
          '$pages page(s)'
          '${discarded > 0 ? ', $discarded discarded as mismatched' : ''}',
    );

    return DriveStateDiscoveryResult(candidates: _newestFirst(candidates));
  }

  DriveStateArtifactCandidate _toCandidate(TransactionCommonMixin node) {
    final tags = <String, String>{};
    for (final tag in node.tags) {
      // First wins. A transaction may carry a tag name twice; taking the first
      // matches how `getTag` reads tags everywhere else in the app.
      tags.putIfAbsent(tag.name, () => tag.value);
    }

    return DriveStateArtifactCandidate(
      txId: node.id,
      ownerAddress: node.owner.address,
      bundledInTxId: node.bundledIn?.id,
      minedAtHeight: node.block?.height,
      minedAtTimestamp: node.block?.timestamp,
      tags: tags,
    );
  }

  /// Re-checks client-side what the query already asked for.
  ///
  /// The filters are in the query, so this should never drop anything. It
  /// exists because the indexer is untrusted (§4.1, §4.2) and the owner filter
  /// in particular is the one thing GraphQL discovery proves that a name
  /// cannot — an artifact attributed to anyone but the drive owner must not
  /// reach a caller under any indexer behaviour.
  bool _isUsable(
    DriveStateArtifactCandidate candidate, {
    required String driveId,
    required String ownerAddress,
  }) =>
      candidate.ownerAddress == ownerAddress &&
      candidate.driveId == driveId &&
      candidate.entityType == EntityTypeTag.driveState;

  /// Newest first by `Block-End` (§3.4: a later artifact supersedes every
  /// earlier one outright).
  ///
  /// An artifact with no parseable `Block-End` sorts last rather than being
  /// dropped: it is the verification path's job to reject it, with a reason.
  /// Ties fall back to mined height, then `Unix-Time`, then the transaction id
  /// so the order is total and a test is not at the mercy of list order.
  static List<DriveStateArtifactCandidate> _newestFirst(
    List<DriveStateArtifactCandidate> candidates,
  ) {
    final sorted = [...candidates];
    sorted.sort((a, b) {
      final byBlockEnd = _descendingNullsLast(a.blockEnd, b.blockEnd);
      if (byBlockEnd != 0) return byBlockEnd;

      final byHeight = _descendingNullsLast(a.minedAtHeight, b.minedAtHeight);
      if (byHeight != 0) return byHeight;

      final byTime = _descendingNullsLast(a.unixTime, b.unixTime);
      if (byTime != 0) return byTime;

      return a.txId.compareTo(b.txId);
    });
    return List.unmodifiable(sorted);
  }

  static int _descendingNullsLast(int? a, int? b) {
    if (a == b) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }
}
