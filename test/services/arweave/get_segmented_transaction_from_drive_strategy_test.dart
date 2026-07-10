import 'package:ardrive/services/arweave/get_segmented_transaction_from_drive_strategy.dart';
import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/utils/graphql_retry.dart';
import 'package:artemis/schema/graphql_query.dart';
import 'package:artemis/schema/graphql_response.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:json_annotation/json_annotation.dart';

class CallRecord {
  final int? pageSize;
  final String? after;
  final bool allowFallback;
  final bool useFallbackEndpoint;
  final int maxAttempts;

  CallRecord({
    required this.pageSize,
    required this.after,
    required this.allowFallback,
    required this.useFallbackEndpoint,
    required this.maxAttempts,
  });
}

typedef PageHandler
    = Future<GraphQLResponse<DriveEntityHistoryWithoutEntityTypeFilter$Query>>
        Function(CallRecord call);

/// Hand-rolled fake: records every call's page size, cursor, and endpoint
/// flags, and delegates the response to a scripted handler.
class ScriptedGraphQLRetry implements GraphQLRetry {
  final PageHandler handler;
  final List<CallRecord> calls = [];

  ScriptedGraphQLRetry(this.handler);

  @override
  Future<GraphQLResponse<T>> execute<T, U extends JsonSerializable>(
    GraphQLQuery<T, U> query, {
    Function(Exception e)? onRetry,
    int maxAttempts = 8,
    bool allowFallback = true,
    bool useFallbackEndpoint = false,
  }) async {
    final vars = (query as DriveEntityHistoryWithoutEntityTypeFilterQuery)
        .variables;
    final record = CallRecord(
      pageSize: vars.pageSize,
      after: vars.after,
      allowFallback: allowFallback,
      useFallbackEndpoint: useFallbackEndpoint,
      maxAttempts: maxAttempts,
    );
    calls.add(record);
    return await handler(record) as GraphQLResponse<T>;
  }
}

GraphQLResponse<DriveEntityHistoryWithoutEntityTypeFilter$Query> page(
  List<String> txIds, {
  required bool hasNextPage,
  String arfsVersion = '0.11',
}) {
  return GraphQLResponse(
    data: DriveEntityHistoryWithoutEntityTypeFilter$Query.fromJson({
      'transactions': {
        'pageInfo': {'hasNextPage': hasNextPage},
        'edges': [
          for (final id in txIds)
            {
              'cursor': 'cursor-$id',
              'node': {
                'id': id,
                'owner': {'address': 'owner-address'},
                'tags': [
                  {'name': 'ArFS', 'value': arfsVersion},
                ],
                'block': {'height': 100, 'timestamp': 1000},
              },
            },
        ],
      },
    }),
  );
}

void main() {
  const driveId = 'drive-1';
  const owner = 'owner-address';

  Stream<List<dynamic>> run(
    ScriptedGraphQLRetry retry, {
    int pageSize = 1000,
    Set<String>? ownersPreferringFallback,
  }) {
    final strategy =
        GetSegmentedTransactionFromDriveWithoutEntityTypeFilterStrategy(
      retry,
      pageSize: pageSize,
      ownersPreferringFallback: ownersPreferringFallback,
    );
    return strategy.getSegmentedTransactionFromDrive(
      driveId,
      ownerAddress: owner,
    );
  }

  Future<List<String>> collectIds(Stream<List<dynamic>> stream) async {
    final ids = <String>[];
    await for (final batch in stream) {
      for (final t in batch) {
        ids.add(t.transactionCommonMixin.id as String);
      }
    }
    return ids;
  }

  group('phase A (primary, large pages)', () {
    test('paginates at the configured page size with fallback disabled',
        () async {
      final retry = ScriptedGraphQLRetry((call) async {
        if (call.after == null) {
          return page(['tx-1', 'tx-2'], hasNextPage: true);
        }
        if (call.after == 'cursor-tx-2') {
          return page(['tx-3'], hasNextPage: false);
        }
        // End-of-range verification page (every non-empty final page of an
        // oversized request gets one).
        expect(call.after, 'cursor-tx-3');
        return page([], hasNextPage: false);
      });

      final ids = await collectIds(run(retry));

      expect(ids, ['tx-1', 'tx-2', 'tx-3']);
      expect(retry.calls, hasLength(3));
      expect(retry.calls[0].pageSize, 1000);
      expect(retry.calls[1].pageSize, 1000);
      expect(retry.calls[2].pageSize, kFallbackGqlPageSize,
          reason: 'verification page runs at the safe page size');
      for (final call in retry.calls) {
        expect(call.allowFallback, isFalse);
        expect(call.useFallbackEndpoint, isFalse);
      }
    });

    test('advances the cursor from raw edges even when a page is entirely '
        'filtered out', () async {
      final retry = ScriptedGraphQLRetry((call) async {
        if (call.after == null) {
          // Unsupported ArFS version: everything filtered out.
          return page(['tx-old-1', 'tx-old-2'],
              hasNextPage: true, arfsVersion: '9.99');
        }
        // Cursor must come from raw edges, not the (empty) filtered list.
        if (call.after == 'cursor-tx-old-2') {
          return page(['tx-3'], hasNextPage: false);
        }
        expect(call.after, 'cursor-tx-3');
        return page([], hasNextPage: false);
      });

      final ids = await collectIds(run(retry));

      expect(ids, ['tx-3']);
    });
  });

  group('clamp guard', () {
    test('does not trust hasNextPage=false on a suspiciously full page',
        () async {
      final fullPage = List.generate(100, (i) => 'tx-$i');
      final retry = ScriptedGraphQLRetry((call) async {
        if (call.after == null) {
          // Clamping gateway: 100 edges, lies about hasNextPage.
          return page(fullPage, hasNextPage: false);
        }
        // Verification page continues from the clamp boundary at 100.
        expect(call.pageSize, kFallbackGqlPageSize);
        expect(call.after, 'cursor-tx-99');
        return page(['tx-100'], hasNextPage: false);
      });

      final ids = await collectIds(run(retry));

      expect(ids, hasLength(101), reason: 'clamped tail must be recovered');
      expect(retry.calls, hasLength(2));
    });

    test('catches gateways that clamp below 100 as well', () async {
      final tenEdges = List.generate(10, (i) => 'tx-$i');
      final retry = ScriptedGraphQLRetry((call) async {
        if (call.after == null) {
          // Gateway clamps first:1000 down to its own default of 10 and
          // falsely reports the range as complete.
          return page(tenEdges, hasNextPage: false);
        }
        expect(call.after, 'cursor-tx-9');
        return page(['tx-10'], hasNextPage: false);
      });

      final ids = await collectIds(run(retry));

      expect(ids, hasLength(11), reason: 'clamped tail must be recovered');
    });

    test('a genuinely complete 100-edge page costs one empty verification '
        'page', () async {
      final fullPage = List.generate(100, (i) => 'tx-$i');
      final retry = ScriptedGraphQLRetry((call) async {
        if (call.after == null) {
          return page(fullPage, hasNextPage: false);
        }
        return page([], hasNextPage: false);
      });

      final ids = await collectIds(run(retry));

      expect(ids, hasLength(100));
      expect(retry.calls, hasLength(2));
    });
  });

  group('phase ladder', () {
    test('downshifts to small pages on the primary when large pages fail, '
        'deduplicating the restarted range', () async {
      final retry = ScriptedGraphQLRetry((call) async {
        if (call.pageSize == 1000) {
          if (call.after == null) {
            return page(['tx-1', 'tx-2'], hasNextPage: true);
          }
          throw GraphQLException('boom mid-pagination');
        }
        // Phase B: restarted from the beginning at the safe page size.
        expect(call.useFallbackEndpoint, isFalse);
        expect(call.after, isNull);
        return page(['tx-1', 'tx-2', 'tx-3'], hasNextPage: false);
      });

      final ids = await collectIds(run(retry));

      expect(ids, ['tx-1', 'tx-2', 'tx-3'],
          reason: 'restart must not re-yield tx-1/tx-2');
    });

    test('falls back to the fallback endpoint and records the owner',
        () async {
      final owners = <String>{};
      final retry = ScriptedGraphQLRetry((call) async {
        if (!call.useFallbackEndpoint) {
          throw GraphQLException('indexer cannot serve this owner');
        }
        expect(call.pageSize, kFallbackGqlPageSize);
        return page(['tx-1'], hasNextPage: false);
      });

      final ids =
          await collectIds(run(retry, ownersPreferringFallback: owners));

      expect(ids, ['tx-1']);
      expect(owners, contains(owner));
      // Phase A (1000) + phase B (100) + phase C (fallback).
      expect(retry.calls.map((c) => c.useFallbackEndpoint).toList(),
          [false, false, true]);
    });

    test('owners already known to need the fallback skip the primary phases',
        () async {
      final retry = ScriptedGraphQLRetry((call) async {
        expect(call.useFallbackEndpoint, isTrue);
        return page(['tx-1'], hasNextPage: false);
      });

      final ids = await collectIds(
          run(retry, ownersPreferringFallback: {owner}));

      expect(ids, ['tx-1']);
      expect(retry.calls, hasLength(1));
    });

    test('propagates the error when every phase fails', () async {
      final retry = ScriptedGraphQLRetry((call) async {
        throw GraphQLException('everything is down');
      });

      await expectLater(
        collectIds(run(retry)),
        throwsA(isA<GraphQLException>()),
      );
    });
  });

  group('misbehaving gateways fail loudly instead of truncating', () {
    test('empty page with hasNextPage=true throws', () async {
      final retry = ScriptedGraphQLRetry((call) async {
        return page([], hasNextPage: true);
      });

      await expectLater(
        collectIds(run(retry, ownersPreferringFallback: {owner})),
        throwsA(isA<GraphQLException>()),
      );
    });

    test('null data with no errors throws', () async {
      final retry = ScriptedGraphQLRetry((call) async {
        return GraphQLResponse(data: null);
      });

      await expectLater(
        collectIds(run(retry, ownersPreferringFallback: {owner})),
        throwsA(isA<GraphQLException>()),
      );
    });
  });

  group('small configured page size', () {
    test('skips phase B and never exceeds the fallback page size', () async {
      var primaryCalls = 0;
      final retry = ScriptedGraphQLRetry((call) async {
        expect(call.pageSize, kFallbackGqlPageSize);
        if (!call.useFallbackEndpoint) {
          primaryCalls++;
          throw GraphQLException('primary down');
        }
        return page(['tx-1'], hasNextPage: false);
      });

      final ids =
          await collectIds(run(retry, pageSize: kFallbackGqlPageSize));

      expect(ids, ['tx-1']);
      expect(primaryCalls, 1, reason: 'phase B is redundant at 100');
    });
  });
}
