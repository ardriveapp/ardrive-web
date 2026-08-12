import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/arweave/data_gateway_fallback.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:mocktail/mocktail.dart';

class _MockArioSDK extends Mock implements ArioSDK {}

class _MockArweave extends Mock implements Arweave {}

class _MockArweaveApi extends Mock implements ArweaveApi {}

void main() {
  late _MockArioSDK arioSDK;
  late _MockArweave primaryClient;
  late _MockArweaveApi primaryApi;
  late DataGatewayFallback fallback;

  const txId = 'a-transaction-id';

  setUp(() {
    arioSDK = _MockArioSDK();
    primaryClient = _MockArweave();
    primaryApi = _MockArweaveApi();

    when(() => primaryClient.api).thenReturn(primaryApi);
    when(() => primaryApi.gatewayUrl)
        .thenReturn(Uri.parse('https://configured-gateway.example'));
    // Returning an empty list keeps the waterfall from making real network
    // calls while still letting us verify whether the GAR was consulted.
    when(() => arioSDK.getGateways()).thenAnswer((_) async => <Gateway>[]);

    fallback = DataGatewayFallback(arioSDK: arioSDK);
  });

  group('fetchDataForSync — single configured gateway', () {
    test('returns the response without retrying when the first attempt '
        'succeeds', () async {
      when(() => primaryApi.getSandboxedTx(txId))
          .thenAnswer((_) async => Response('metadata', 200));

      final response = await fallback.fetchDataForSync(txId, primaryClient);

      expect(response.statusCode, 200);
      expect(response.body, 'metadata');
      verify(() => primaryApi.getSandboxedTx(txId)).called(1);
    });

    test('retries a transient failure exactly once, then succeeds', () async {
      var attempts = 0;
      when(() => primaryApi.getSandboxedTx(txId)).thenAnswer((_) async {
        attempts++;
        if (attempts == 1) throw Exception('connection reset');
        return Response('metadata', 200);
      });

      final response = await fallback.fetchDataForSync(txId, primaryClient);

      expect(response.statusCode, 200);
      expect(attempts, 2);
    });

    test('gives up after two attempts on a persistent transient failure, so '
        'the caller can skip the item', () async {
      when(() => primaryApi.getSandboxedTx(txId))
          .thenAnswer((_) async => Response('boom', 500));

      await expectLater(
        fallback.fetchDataForSync(txId, primaryClient),
        throwsA(isA<Exception>()),
      );

      verify(() => primaryApi.getSandboxedTx(txId))
          .called(DataGatewayFallback.syncMaxAttempts);
      expect(DataGatewayFallback.syncMaxAttempts, 2);
    });

    test('retries a 404, because a gateway mid-index answers one', () async {
      // Observed in the wild: a drive signature 404ed once and resolved on the
      // retry. The gateway had the transaction, it just had not indexed it
      // yet. Treating the first 404 as final cost a whole drive.
      var calls = 0;
      when(() => primaryApi.getSandboxedTx(txId)).thenAnswer((_) async {
        calls++;
        return calls == 1
            ? Response('not found', 404)
            : Response('metadata', 200);
      });

      final response = await fallback.fetchDataForSync(txId, primaryClient);

      expect(response.statusCode, 200);
      expect(calls, 2);
    });

    test('reports a transaction absent from every attempt as not found',
        () async {
      when(() => primaryApi.getSandboxedTx(txId))
          .thenAnswer((_) async => Response('not found', 404));

      await expectLater(
        fallback.fetchDataForSync(txId, primaryClient),
        throwsA(isA<TransactionNotFound>()),
      );

      // Bounded: a genuinely missing transaction still costs only the two
      // attempts every other sync read gets.
      verify(() => primaryApi.getSandboxedTx(txId)).called(2);
    });

    test('a 500 then a 404 is not reported as not found', () async {
      // Only every attempt agreeing earns `TransactionNotFound`. A gateway
      // that errored once and 404ed once has not told us the data is absent.
      var calls = 0;
      when(() => primaryApi.getSandboxedTx(txId)).thenAnswer((_) async {
        calls++;
        return calls == 1
            ? Response('boom', 500)
            : Response('not found', 404);
      });

      await expectLater(
        fallback.fetchDataForSync(txId, primaryClient),
        throwsA(allOf(isA<Exception>(), isNot(isA<TransactionNotFound>()))),
      );

      expect(calls, 2);
    });

    test('a thrown error then a 404 is not reported as not found', () async {
      var calls = 0;
      when(() => primaryApi.getSandboxedTx(txId)).thenAnswer((_) async {
        calls++;
        if (calls == 1) throw Exception('socket closed');
        return Response('not found', 404);
      });

      await expectLater(
        fallback.fetchDataForSync(txId, primaryClient),
        throwsA(allOf(isA<Exception>(), isNot(isA<TransactionNotFound>()))),
      );

      expect(calls, 2);
    });

    test('never consults the GAR, so no Solana RPC is issued on the sync path',
        () async {
      when(() => primaryApi.getSandboxedTx(txId))
          .thenAnswer((_) async => Response('boom', 500));

      await expectLater(
        fallback.fetchDataForSync(txId, primaryClient),
        throwsA(isA<Exception>()),
      );

      verifyNever(() => arioSDK.getGateways());
      expect(fallback.cachedGateways, isNull);
    });

    test('never falls back to another host', () async {
      when(() => primaryApi.getSandboxedTx(txId))
          .thenAnswer((_) async => Response('boom', 503));

      await expectLater(
        fallback.fetchDataForSync(txId, primaryClient),
        throwsA(isA<Exception>()),
      );

      // Only the configured gateway's api was ever asked for a transaction.
      verify(() => primaryApi.getSandboxedTx(txId)).called(2);
      verifyNever(() => arioSDK.getGateways());
    });

    /// The default budget is sized for the metadata reads that dominate sync,
    /// a few hundred bytes each. A snapshot is the same call with a body four
    /// orders of magnitude larger - this user's newest is 43.9 MiB, which a
    /// warm gateway serves in ~8s - so under the metadata budget it could
    /// never finish on any connection slower than ~9 MB/s, however many times
    /// it was retried.
    group('large bodies', () {
      /// Scaled down so the test does not spend the real budgets, which are
      /// measured in tens of seconds. What is asserted is that `largeBody`
      /// routes to the larger of the two, and that the default cannot carry a
      /// body that outlives it.
      late DataGatewayFallback scaled;

      setUp(() {
        scaled = DataGatewayFallback(
          arioSDK: arioSDK,
          syncRequestTimeout: const Duration(milliseconds: 100),
          syncLargeBodyRequestTimeout: const Duration(seconds: 5),
        );
      });

      test('a snapshot-sized read outlives the metadata budget', () async {
        when(() => primaryApi.getSandboxedTx(txId)).thenAnswer((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          return Response('a snapshot body', 200);
        });

        final response = await scaled.fetchDataForSync(
          txId,
          primaryClient,
          largeBody: true,
        );

        expect(response.statusCode, 200);
        expect(response.body, 'a snapshot body');
        verify(() => primaryApi.getSandboxedTx(txId)).called(1);
      });

      test('the same read fails on the default budget', () async {
        when(() => primaryApi.getSandboxedTx(txId)).thenAnswer((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          return Response('a snapshot body', 200);
        });

        // Times out, retries, times out again - which is what a 44 MiB
        // snapshot did against a budget meant for metadata.
        await expectLater(
          scaled.fetchDataForSync(txId, primaryClient),
          throwsA(isA<Exception>()),
        );
        verify(() => primaryApi.getSandboxedTx(txId)).called(2);
      });
    });
  });

  group('waterfall preserved for non-sync paths', () {
    test('fetchData still consults the GAR (download/preview resilience)',
        () async {
      when(() => primaryApi.getSandboxedTx(txId))
          .thenAnswer((_) async => Response('metadata', 200));

      await fallback.fetchData(txId, primaryClient);

      verify(() => arioSDK.getGateways()).called(1);
    });

    test('downloadWithFallback still consults the GAR', () async {
      // The download itself will fail against the fake client; all we assert
      // is that the client list was built from the GAR.
      await expectLater(
        fallback.downloadWithFallback(
          txId: txId,
          primaryClient: primaryClient,
        ),
        throwsA(isA<Object>()),
      );

      verify(() => arioSDK.getGateways()).called(1);
    });

    test('fetchData and fetchDataForSync differ in GAR usage for the same '
        'transaction', () async {
      when(() => primaryApi.getSandboxedTx(txId))
          .thenAnswer((_) async => Response('metadata', 200));

      await fallback.fetchDataForSync(txId, primaryClient);
      verifyNever(() => arioSDK.getGateways());

      await fallback.fetchData(txId, primaryClient);
      verify(() => arioSDK.getGateways()).called(1);
    });

    /// A gateway mid-index answers 404 and then 200 a moment later, which
    /// `fetchDataForSync` already accounts for. Walking away from the
    /// configured gateway on its first 404 is worst for exactly the data most
    /// likely to be behind: something just uploaded through Turbo can be on
    /// the configured gateway and nowhere else yet.
    test('retries the configured gateway once on a 404, then succeeds',
        () async {
      var attempts = 0;
      when(() => primaryApi.getSandboxedTx(txId)).thenAnswer((_) async {
        attempts++;
        return attempts == 1
            ? Response('not found', 404)
            : Response('metadata', 200);
      });

      final response = await fallback.fetchData(txId, primaryClient);

      expect(response.statusCode, 200);
      expect(response.body, 'metadata');
      verify(() => primaryApi.getSandboxedTx(txId)).called(2);
    });

    /// The extra attempt is for a gateway that is a beat behind, not one that
    /// is unwell. A refusal or an error has already cost its timeout and says
    /// the next gateway is the better bet.
    test('does not retry the configured gateway on a non-404 failure',
        () async {
      // arweave.net as the primary so it is the only client in the list, which
      // keeps the assertion about retries free of any real network call.
      when(() => primaryApi.gatewayUrl)
          .thenReturn(Uri.parse('https://arweave.net'));
      when(() => primaryApi.getSandboxedTx(txId))
          .thenAnswer((_) async => Response('server error', 500));

      await expectLater(
        fallback.fetchData(txId, primaryClient),
        throwsA(isA<Object>()),
      );

      verify(() => primaryApi.getSandboxedTx(txId)).called(1);
    });

    test('a persistent 404 on the configured gateway is still not found',
        () async {
      when(() => primaryApi.gatewayUrl)
          .thenReturn(Uri.parse('https://arweave.net'));
      when(() => primaryApi.getSandboxedTx(txId))
          .thenAnswer((_) async => Response('not found', 404));

      await expectLater(
        fallback.fetchData(txId, primaryClient),
        throwsA(isA<TransactionNotFound>()),
      );

      verify(() => primaryApi.getSandboxedTx(txId)).called(2);
    });

    test('a drive signature read on the sync path never reaches the GAR',
        () async {
      // Drive discovery fetches this for every private drive whose key is not
      // already in memory. It used to go through `getDriveSignatureForDrive`,
      // which is the login path and uses the waterfall — putting the fan-out
      // back into sync one drive at a time.
      const signatureTxId = 'gPzMbUCLZ_1lJ6mCLQK4vGLtiOTKn1TfnCU8gLuLBLM';

      when(() => primaryApi.getSandboxedTx(signatureTxId))
          .thenAnswer((_) async => Response('signature', 200));

      await fallback.fetchDataForSync(signatureTxId, primaryClient);

      verifyNever(() => arioSDK.getGateways());
      expect(fallback.cachedGateways, isNull);
    });
  });

  group('ArweaveService.runPooled', () {
    test('writes results positionally when tasks complete out of order',
        () async {
      // Later indices finish first, so appending would scramble the output.
      final results = List<int?>.filled(6, null);
      final delaysMs = [60, 50, 40, 30, 20, 10];

      await ArweaveService.runPooled(
        concurrency: 3,
        itemCount: 6,
        task: (i) async {
          await Future.delayed(Duration(milliseconds: delaysMs[i]));
          results[i] = i;
        },
      );

      expect(results, [0, 1, 2, 3, 4, 5]);
    });

    test('keeps at most `concurrency` tasks in flight', () async {
      var inFlight = 0;
      var maxObserved = 0;

      await ArweaveService.runPooled(
        concurrency: 4,
        itemCount: 20,
        task: (i) async {
          inFlight++;
          maxObserved = inFlight > maxObserved ? inFlight : maxObserved;
          await Future.delayed(const Duration(milliseconds: 5));
          inFlight--;
        },
      );

      expect(maxObserved, 4);
      expect(inFlight, 0);
    });

    test('runs every index exactly once', () async {
      final seen = <int>[];

      await ArweaveService.runPooled(
        concurrency: 5,
        itemCount: 50,
        task: (i) async {
          await Future.delayed(const Duration(milliseconds: 1));
          seen.add(i);
        },
      );

      expect(seen.length, 50);
      expect(seen.toSet().length, 50);
    });

    test('one slow task does not stall unrelated items', () async {
      // Index 0 is slow; with a chunked barrier the other workers would idle
      // until it finished. Pooled, they should stream through it.
      final completionOrder = <int>[];

      await ArweaveService.runPooled(
        concurrency: 2,
        itemCount: 6,
        task: (i) async {
          await Future.delayed(
            Duration(milliseconds: i == 0 ? 120 : 5),
          );
          completionOrder.add(i);
        },
      );

      // The slow item finishes last despite being claimed first.
      expect(completionOrder.last, 0);
      expect(completionOrder.length, 6);
    });

    test('clamps worker count to itemCount and handles an empty workload',
        () async {
      var ran = 0;

      await ArweaveService.runPooled(
        concurrency: 10,
        itemCount: 2,
        task: (_) async => ran++,
      );
      expect(ran, 2);

      await ArweaveService.runPooled(
        concurrency: 10,
        itemCount: 0,
        task: (_) async => fail('should not run'),
      );
    });
  });
}
