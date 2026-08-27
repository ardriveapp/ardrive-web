import 'package:ardrive/drive_state/domain/drive_state_format_version.dart';
import 'package:ardrive/drive_state/data/drive_state_discovery.dart';
import 'package:ardrive/drive_state/domain/drive_state_outcome.dart';
import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/utils/graphql_retry.dart';
import 'package:artemis/schema/graphql_query.dart';
import 'package:artemis/schema/graphql_response.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:json_annotation/json_annotation.dart';

/// The one version this build writes and reads. Tests follow the constant
/// rather than restating it, so moving the format version does not mean
/// editing every fixture — which is how a fixture ends up asserting a
/// version the code no longer speaks.
String get currentVersionString => DriveStateFormatVersion.current.toString();

const _driveId = 'a4d2b9a5-2ac6-4c1e-8f4f-1a4a3e2d1c00';
const _owner = 'OWNER_ADDRESS';
const _otherOwner = 'SOMEONE_ELSE';

/// Stands in for the GraphQL endpoint. Hand written rather than mocked because
/// discovery cares about *sequences* — pages, cursors, a failure part-way —
/// which read far better as a queue of scripted answers.
class _ScriptedGraphQLRetry implements GraphQLRetry {
  _ScriptedGraphQLRetry(this._answers);

  /// Each entry is either a `Map<String, dynamic>` response body, `null` for a
  /// response that carries no data, or an `Object` to throw.
  final List<Object?> _answers;

  final List<DriveStateEntityHistoryArguments> calls = [];
  int _index = 0;

  @override
  Future<GraphQLResponse<T>> execute<T, U extends JsonSerializable>(
    GraphQLQuery<T, U> query, {
    Function(Exception e)? onRetry,
    int maxAttempts = GraphQLRetry.defaultMaxAttempts,
  }) async {
    calls.add(query.variables as DriveStateEntityHistoryArguments);

    final answer = _answers[_index++];

    if (answer == null) {
      return GraphQLResponse<T>(data: null);
    }
    if (answer is Map<String, dynamic>) {
      return GraphQLResponse(data: query.parse(answer));
    }
    throw answer;
  }
}

Map<String, dynamic> _tx({
  required String id,
  String owner = _owner,
  String driveId = _driveId,
  String entityType = 'drive-state',
  int? blockEnd,
  int? blockHeight,
  int? unixTime,
  String? rawBlockEnd,
  String? bundledIn,
  Map<String, String> extraTags = const {},
}) {
  final tags = <Map<String, String>>[
    {'name': 'ArFS', 'value': '0.15'},
    {'name': 'Entity-Type', 'value': entityType},
    {'name': 'Drive-Id', 'value': driveId},
    if (rawBlockEnd != null)
      {'name': 'Block-End', 'value': rawBlockEnd}
    else if (blockEnd != null)
      {'name': 'Block-End', 'value': '$blockEnd'},
    {'name': 'Block-Start', 'value': '0'},
    if (unixTime != null) {'name': 'Unix-Time', 'value': '$unixTime'},
    ...extraTags.entries.map((e) => {'name': e.key, 'value': e.value}),
  ];

  return {
    'id': id,
    'owner': {'address': owner},
    'bundledIn': bundledIn == null ? null : {'id': bundledIn},
    'block': blockHeight == null
        ? null
        : {'height': blockHeight, 'timestamp': 1700000000},
    'tags': tags,
  };
}

Map<String, dynamic> _page(
  List<Map<String, dynamic>> nodes, {
  bool hasNextPage = false,
  String cursorPrefix = 'c',
}) =>
    {
      'transactions': {
        'pageInfo': {'hasNextPage': hasNextPage},
        'edges': [
          for (var i = 0; i < nodes.length; i++)
            {'cursor': '$cursorPrefix$i', 'node': nodes[i]},
        ],
      },
    };

void main() {
  late List<String> logLines;
  late DriveStateOutcomeReporter reporter;

  setUp(() {
    logLines = [];
    reporter = DriveStateOutcomeReporter(
      sink: (_, message) => logLines.add(message),
    );
  });

  GraphQLDriveStateDiscovery discovery(
    _ScriptedGraphQLRetry gql, {
    int maxPages = 1,
  }) =>
      GraphQLDriveStateDiscovery(
        graphQLRetry: gql,
        reporter: reporter,
        maxPages: maxPages,
      );

  group('GraphQLDriveStateDiscovery', () {
    test('asks for this drive, this owner, and drive-state only', () async {
      final gql = _ScriptedGraphQLRetry([_page([])]);

      await discovery(gql).findCandidates(
        driveId: _driveId,
        ownerAddress: _owner,
        minBlockHeight: 1800000,
      );

      expect(gql.calls.single.driveIds, [_driveId]);
      expect(gql.calls.single.ownerAddress, _owner);
      expect(gql.calls.single.minBlockHeight, 1800000);
    });

    test('returns candidates newest first by Block-End', () async {
      final gql = _ScriptedGraphQLRetry([
        _page([
          _tx(id: 'MIDDLE', blockEnd: 1500000, blockHeight: 1500001),
          _tx(id: 'OLDEST', blockEnd: 1000000, blockHeight: 1000001),
          _tx(id: 'NEWEST', blockEnd: 1814228, blockHeight: 1814230),
        ]),
      ]);

      final result = await discovery(gql)
          .findCandidates(driveId: _driveId, ownerAddress: _owner);

      expect(
        result.candidates.map((c) => c.txId),
        ['NEWEST', 'MIDDLE', 'OLDEST'],
      );
      expect(result.newest!.txId, 'NEWEST');
      expect(result.discoveryFailed, isFalse);
    });

    test('sorts an unreadable Block-End last instead of dropping it', () async {
      // Rejecting it is the verification path's job, with a reason. Discovery
      // dropping it silently would be exactly the invisible fallback §7 is
      // about.
      final gql = _ScriptedGraphQLRetry([
        _page([
          _tx(id: 'UNREADABLE', rawBlockEnd: 'not-a-number'),
          _tx(id: 'GOOD', blockEnd: 1000000),
        ]),
      ]);

      final result = await discovery(gql)
          .findCandidates(driveId: _driveId, ownerAddress: _owner);

      expect(result.candidates.map((c) => c.txId), ['GOOD', 'UNREADABLE']);
      expect(result.candidates.last.blockEnd, isNull);
    });

    test('excludes artifacts from a different owner', () async {
      // The query filters on `owners:`, so this should be impossible. It is
      // checked anyway: §4.2 says GraphQL discovery's one advantage over a
      // name is that it proves authorship, and an indexer is the least
      // trustworthy component in the stack.
      final gql = _ScriptedGraphQLRetry([
        _page([
          _tx(id: 'IMPOSTOR', owner: _otherOwner, blockEnd: 1900000),
          _tx(id: 'MINE', blockEnd: 1000000),
        ]),
      ]);

      final result = await discovery(gql)
          .findCandidates(driveId: _driveId, ownerAddress: _owner);

      expect(result.candidates.map((c) => c.txId), ['MINE']);
      expect(result.newest!.ownerAddress, _owner);
    });

    test('excludes another drive and another entity type', () async {
      final gql = _ScriptedGraphQLRetry([
        _page([
          _tx(
              id: 'OTHER_DRIVE',
              driveId: 'some-other-drive',
              blockEnd: 1900000),
          _tx(id: 'A_SNAPSHOT', entityType: 'snapshot', blockEnd: 1800000),
          _tx(id: 'MINE', blockEnd: 1000000),
        ]),
      ]);

      final result = await discovery(gql)
          .findCandidates(driveId: _driveId, ownerAddress: _owner);

      expect(result.candidates.map((c) => c.txId), ['MINE']);
      expect(logLines.last, contains('2 discarded as mismatched'));
    });

    test('reads a bundled data item and an L1 transaction alike', () async {
      final gql = _ScriptedGraphQLRetry([
        _page([
          _tx(id: 'BUNDLED', blockEnd: 1900000, bundledIn: 'BUNDLE_TX'),
          _tx(id: 'LAYER_ONE', blockEnd: 1800000),
        ]),
      ]);

      final result = await discovery(gql)
          .findCandidates(driveId: _driveId, ownerAddress: _owner);

      expect(result.candidates.map((c) => c.txId), ['BUNDLED', 'LAYER_ONE']);
      expect(result.candidates.first.isBundled, isTrue);
      expect(result.candidates.first.bundledInTxId, 'BUNDLE_TX');
      expect(result.candidates.last.isBundled, isFalse);
    });

    test('parses the tags a reader needs before fetching', () async {
      final gql = _ScriptedGraphQLRetry([
        _page([
          _tx(
            id: 'TX',
            blockEnd: 1814228,
            blockHeight: 1814230,
            unixTime: 1700000123,
            extraTags: {
              'Drive-State-Id': 'STATE_UUID',
              'State-Version': currentVersionString,
              'Content-Encoding': 'gzip',
              'Entity-Count': '12043',
              'Cipher': 'AES256-GCM',
              'Cipher-IV': 'BASE64IV',
              'Data-Start': '900000',
              'Data-End': '1814000',
            },
          ),
        ]),
      ]);

      final candidate = (await discovery(gql)
              .findCandidates(driveId: _driveId, ownerAddress: _owner))
          .newest!;

      expect(candidate.driveId, _driveId);
      expect(candidate.entityType, 'drive-state');
      expect(candidate.arFsVersion, '0.15');
      expect(candidate.driveStateId, 'STATE_UUID');
      expect(candidate.stateVersion, '1.0');
      expect(candidate.contentEncoding, 'gzip');
      expect(candidate.entityCount, 12043);
      expect(candidate.cipher, 'AES256-GCM');
      expect(candidate.cipherIv, 'BASE64IV');
      expect(candidate.blockStart, 0);
      expect(candidate.blockEnd, 1814228);
      expect(candidate.dataStart, 900000);
      expect(candidate.dataEnd, 1814000);
      expect(candidate.unixTime, 1700000123);
      expect(candidate.minedAtHeight, 1814230);
      // §6: unknown tags are ignored, not rejected, and stay readable.
      expect(candidate.tag('Block-Start'), '0');
      expect(candidate.tag('No-Such-Tag'), isNull);
    });

    test('returns empty and never throws when the query fails', () async {
      final gql = _ScriptedGraphQLRetry([Exception('gateway on fire')]);

      final result = await discovery(gql)
          .findCandidates(driveId: _driveId, ownerAddress: _owner);

      expect(result.candidates, isEmpty);
      expect(result.isEmpty, isTrue);
      expect(result.newest, isNull);
      // A failed lookup is not "this drive has no artifact" - §7 forbids those
      // reading the same, and the caller needs the difference to log honestly.
      expect(result.discoveryFailed, isTrue);
      expect(logLines.single, contains('discovery query failed'));
      expect(logLines.single, contains('gateway on fire'));
    });

    test('keeps what an earlier page found when a later one fails', () async {
      final gql = _ScriptedGraphQLRetry([
        _page([_tx(id: 'FOUND', blockEnd: 1000000)], hasNextPage: true),
        Exception('rate limited'),
      ]);

      final result = await discovery(gql, maxPages: 3)
          .findCandidates(driveId: _driveId, ownerAddress: _owner);

      expect(result.candidates.map((c) => c.txId), ['FOUND']);
      expect(result.discoveryFailed, isTrue);
    });

    test('treats a response with no data as a failure, not as none', () async {
      final gql = _ScriptedGraphQLRetry([null]);

      final result = await discovery(gql)
          .findCandidates(driveId: _driveId, ownerAddress: _owner);

      expect(result.candidates, isEmpty);
      expect(result.discoveryFailed, isTrue);
      expect(logLines.single, contains('returned no data'));
    });

    test('an empty answer is a clean "none", not a failure', () async {
      final gql = _ScriptedGraphQLRetry([_page([])]);

      final result = await discovery(gql)
          .findCandidates(driveId: _driveId, ownerAddress: _owner);

      expect(result.candidates, isEmpty);
      expect(result.discoveryFailed, isFalse);
      expect(logLines.single, contains('0 candidate(s)'));
    });

    test('follows the cursor across pages up to the page budget', () async {
      final gql = _ScriptedGraphQLRetry([
        _page([_tx(id: 'P1', blockEnd: 3000)],
            hasNextPage: true, cursorPrefix: 'pageA_'),
        _page([_tx(id: 'P2', blockEnd: 2000)],
            hasNextPage: true, cursorPrefix: 'pageB_'),
      ]);

      final result = await discovery(gql, maxPages: 2)
          .findCandidates(driveId: _driveId, ownerAddress: _owner);

      expect(result.candidates.map((c) => c.txId), ['P1', 'P2']);
      expect(gql.calls.map((c) => c.after), ['', 'pageA_0']);
      expect(result.discoveryFailed, isFalse);
    });

    test('stops after one page by default', () async {
      final gql = _ScriptedGraphQLRetry([
        _page([_tx(id: 'P1', blockEnd: 3000)], hasNextPage: true),
        _page([_tx(id: 'P2', blockEnd: 2000)]),
      ]);

      final result = await discovery(gql)
          .findCandidates(driveId: _driveId, ownerAddress: _owner);

      expect(gql.calls, hasLength(1));
      expect(result.candidates.map((c) => c.txId), ['P1']);
    });

    test('does not loop on an empty page that claims another', () async {
      // The indexer lies about hasNextPage; the snapshot query guards this the
      // same way, against the same indexer.
      final gql = _ScriptedGraphQLRetry([
        _page([], hasNextPage: true),
        _page([], hasNextPage: true),
      ]);

      final result = await discovery(gql, maxPages: 2)
          .findCandidates(driveId: _driveId, ownerAddress: _owner);

      expect(gql.calls, hasLength(1));
      expect(result.candidates, isEmpty);
      expect(result.discoveryFailed, isFalse);
    });

    test('logs a discovery note that no outcome grep can pick up', () async {
      final gql = _ScriptedGraphQLRetry([_page([])]);

      await discovery(gql)
          .findCandidates(driveId: _driveId, ownerAddress: _owner);

      for (final line in logLines) {
        expect(line, startsWith('[drive-state] $_driveId: '));
        expect(line, isNot(contains('outcome=')));
        expect(line, isNot(contains('artifact rejected')));
        expect(line, isNot(contains('no artifact was used')));
      }
    });
  });

  group('DriveStateDiscoveryResult', () {
    test('distinguishes "nothing found" from "could not ask"', () {
      const none = DriveStateDiscoveryResult.none();
      const failed = DriveStateDiscoveryResult.failed();

      expect(none.isEmpty, isTrue);
      expect(failed.isEmpty, isTrue);
      expect(none.discoveryFailed, isFalse);
      expect(failed.discoveryFailed, isTrue);
      expect(none, isNot(failed));
    });
  });

  group('DriveStateArtifactCandidate', () {
    test('holds its tags read-only', () {
      final candidate = DriveStateArtifactCandidate(
        txId: 'TX',
        ownerAddress: _owner,
        tags: const {'Drive-Id': _driveId},
      );

      expect(
          () => candidate.tags['Drive-Id'] = 'other', throwsUnsupportedError);
    });
  });
}
