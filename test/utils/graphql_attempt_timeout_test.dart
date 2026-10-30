import 'dart:async';

import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/utils/graphql_retry.dart';
import 'package:ardrive/utils/internet_checker.dart';
import 'package:artemis/artemis.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gql_exec/gql_exec.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:mocktail/mocktail.dart';

class _MockInternetChecker extends Mock implements InternetChecker {}

/// Never answers its first [stalls] requests, then answers every one.
class _StallingClient extends Fake implements ArtemisClient {
  _StallingClient({required this.stalls});

  final int stalls;
  int requests = 0;

  @override
  Future<GraphQLResponse<T>> execute<T, U extends JsonSerializable>(
    GraphQLQuery<T, U> query, {
    Context context = const Context(),
  }) {
    requests++;
    if (requests <= stalls) return Completer<GraphQLResponse<T>>().future;
    return Future.value(GraphQLResponse<T>());
  }
}

/// Answers every request, each after [delay]: a slow link.
class _SlowClient extends Fake implements ArtemisClient {
  _SlowClient(this.delay);

  final Duration delay;
  int requests = 0;

  @override
  Future<GraphQLResponse<T>> execute<T, U extends JsonSerializable>(
    GraphQLQuery<T, U> query, {
    Context context = const Context(),
  }) {
    requests++;
    return Future.delayed(delay, () => GraphQLResponse<T>());
  }
}

/// A request the gateway accepted and never answered used to wait for ever:
/// nothing set a deadline, so neither a retry nor the fallback ever ran. It
/// held keyfile log in on "Loading wallet details..." indefinitely.
void main() {
  final query = FirstTxForWalletQuery(
    variables: FirstTxForWalletArguments(owner: 'owner'),
  );

  test('an attempt that never answers is retried', () async {
    final client = _StallingClient(stalls: 1);
    final retry = GraphQLRetry(
      client,
      internetChecker: _MockInternetChecker(),
      attemptTimeout: const Duration(milliseconds: 50),
    );

    await retry.execute(query).timeout(const Duration(seconds: 5));

    expect(client.requests, 2);
  });

  test('an endpoint that never answers fails, rather than waiting', () async {
    final checker = _MockInternetChecker();
    when(checker.isConnected).thenAnswer((_) async => false);
    final client = _StallingClient(stalls: 1000);
    final retry = GraphQLRetry(
      client,
      internetChecker: checker,
      // Refuses at once: no request leaves the machine.
      fallbackGraphqlUrl: 'http://127.0.0.1:9/graphql',
      attemptTimeout: const Duration(milliseconds: 20),
    );

    // Two attempts on the primary, then the fallback, which refuses.
    await expectLater(
      retry.execute(query, maxAttempts: 2).timeout(const Duration(seconds: 5)),
      throwsA(isNot(isA<TimeoutException>())),
    );
    expect(client.requests, 2);
  });

  test('each retry gets longer: 20, 40, then 60 seconds at most', () {
    expect(
      [
        for (var attempt = 1; attempt <= 5; attempt++)
          GraphQLRetry.attemptTimeoutFor(attempt),
      ],
      const [
        Duration(seconds: 20),
        Duration(seconds: 40),
        Duration(seconds: 60),
        Duration(seconds: 60),
        Duration(seconds: 60),
      ],
    );
  });

  // A page that always takes longer than the first attempt's timeout, as on
  // a poor mobile link, is answered once an attempt has time enough.
  test('a slow endpoint gets more time on each retry', () async {
    final client = _SlowClient(const Duration(milliseconds: 150));
    final retry = GraphQLRetry(
      client,
      internetChecker: _MockInternetChecker(),
      attemptTimeout: const Duration(milliseconds: 60),
      maxAttemptTimeout: const Duration(milliseconds: 300),
    );

    await retry.execute(query).timeout(const Duration(seconds: 10));

    // 60 ms and 120 ms time out; 180 ms is enough.
    expect(client.requests, 3);
  });

  test('a stalled endpoint is one another endpoint might not be', () {
    expect(GraphQLRetry.deservesFallback(TimeoutException('stalled')), isTrue);
  });
}
