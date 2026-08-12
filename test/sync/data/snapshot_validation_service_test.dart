import 'dart:async';

import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/services/config/selected_gateway.dart';
import 'package:ardrive/sync/data/snapshot_validation_service.dart';
import 'package:ardrive/utils/snapshots/snapshot_item.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';

/// Records whether the service closed it, which is how a timed-out request is
/// cancelled without the `AbortableRequest` that `http` 1.5.0 would provide.
class _CloseTrackingClient extends BaseClient {
  _CloseTrackingClient(this._inner);

  final Client _inner;
  bool closed = false;

  @override
  Future<StreamedResponse> send(BaseRequest request) => _inner.send(request);

  @override
  void close() {
    closed = true;
    _inner.close();
  }
}

class _MockConfigService extends Mock implements ConfigService {}

class _MockArioSDK extends Mock implements ArioSDK {}

/// The only member [SnapshotValidationService] reads off a snapshot item.
///
/// A real [SnapshotItemOnChain] would drag a GraphQL node and a byte source in
/// with it, none of which the validation path touches.
class _FakeSnapshotItem extends Fake implements SnapshotItem {
  @override
  final String txId = 'Iw3hSMB1kQ9Vpp5rUwx5Z4kv7cKzYwzZ_-7QK4mUuTc';
}

void main() {
  group('SnapshotValidationService', () {
    late _MockConfigService configService;

    setUp(() {
      configService = _MockConfigService();
      when(() => configService.config).thenReturn(
        AppConfig(
          // Unroutable host so the HEAD fails fast without touching a real
          // gateway; validation must still complete and simply reject.
          arweaveGatewayForDataRequest: const SelectedGateway(
            label: 'test',
            url: 'https://localhost:1',
          ),
          allowedDataItemSizeForTurbo: 1,
          stripePublishableKey: '',
        ),
      );
    });

    test('constructor takes no ArioSDK — the GAR fallback is gone', () {
      // A compile-time guarantee: this only builds because `arioSDK` is no
      // longer a required parameter.
      final service = SnapshotValidationService(configService: configService);
      expect(service, isA<SnapshotValidationService>());
    });

    test('rejects a snapshot without ever asking for a gateway list',
        () async {
      final arioSDK = _MockArioSDK();
      // Zero delays: this asserts the GAR is never consulted, not the backoff,
      // and the real delays are measured in seconds.
      final service = SnapshotValidationService(
        configService: configService,
        retryDelays: List<Duration>.filled(3, Duration.zero),
        headTimeout: const Duration(milliseconds: 100),
      );

      // A nonempty list, so validation actually runs: an empty one returns
      // before the loop and would assert nothing at all.
      final verified = await service.validateSnapshotItems([
        _FakeSnapshotItem(),
      ]);

      // The configured gateway is unreachable, so the snapshot is rejected -
      // and on `dev` this is the point where the service would have reached
      // for the GAR list to try a second gateway.
      expect(verified, isEmpty);

      // Vacuous on its own, since the service is never handed this SDK. It is
      // the compile-time signature above that proves the branch is gone; this
      // documents the intent at the call site.
      verifyZeroInteractions(arioSDK);
    });

    /// Measured against turbo-gateway.com (Aug 2026), a snapshot HEAD is
    /// bimodal: sub-second when the gateway can answer from cache, and 23s or
    /// no answer at all within 45s when it cannot. Two attempts lose a
    /// perfectly good snapshot to that, and rejecting one costs a GraphQL
    /// re-walk of its whole block range.
    group('retry budget', () {
      /// Zero delays so the test does not spend the real backoff, which is
      /// deliberately measured in seconds.
      List<Duration> noDelays(int retries) =>
          List<Duration>.filled(retries, Duration.zero);

      test('keeps probing past the old two-attempt budget', () async {
        var calls = 0;
        final client = MockClient((_) async {
          calls++;
          // Fails more times than the previous budget allowed for.
          return calls < 4 ? Response('', 500) : Response('', 200);
        });

        final service = SnapshotValidationService(
          configService: configService,
          clientFactory: () => client,
          retryDelays: noDelays(3),
        );

        final verified =
            await service.validateSnapshotItems([_FakeSnapshotItem()]);

        expect(verified, hasLength(1),
            reason: 'a snapshot that answers on the 4th probe is still usable');
        expect(calls, 4);
      });

      /// A gateway 302s `/{txId}` to its own sandbox subdomain and serves the
      /// body there, and every client this runs on follows that. A 302 that
      /// survives to be inspected is therefore a chain that did not complete,
      /// so the body was never reached - and one of this user's dead
      /// snapshots answers exactly that way, 302 on the first hop and 404 on
      /// the host it points at.
      test('an unfollowed redirect is not proof the body is there', () async {
        var calls = 0;
        final client = MockClient((_) async {
          calls++;
          return Response('', 302);
        });

        final service = SnapshotValidationService(
          configService: configService,
          clientFactory: () => client,
          retryDelays: noDelays(3),
        );

        expect(
          await service.validateSnapshotItems([_FakeSnapshotItem()]),
          isEmpty,
          reason: 'availability is unproven until the body host answers',
        );
        expect(calls, 4, reason: 'a 302 is transient, so it is retried');
      });

      test('spends every attempt before rejecting', () async {
        var calls = 0;
        final client = MockClient((_) async {
          calls++;
          return Response('', 404);
        });

        final service = SnapshotValidationService(
          configService: configService,
          clientFactory: () => client,
          retryDelays: noDelays(3),
        );

        expect(
          await service.validateSnapshotItems([_FakeSnapshotItem()]),
          isEmpty,
        );
        expect(calls, 4);
      });

      /// A refusal is a decision the same host repeats, so spending the budget
      /// on it only delays the GraphQL fallback.
      test('gives up immediately on a non-retryable refusal', () async {
        var calls = 0;
        final client = MockClient((_) async {
          calls++;
          return Response('', 403);
        });

        final service = SnapshotValidationService(
          configService: configService,
          clientFactory: () => client,
          retryDelays: noDelays(3),
        );

        expect(
          await service.validateSnapshotItems([_FakeSnapshotItem()]),
          isEmpty,
        );
        expect(calls, 1);
      });

      test('a timeout is retried like any other transient failure', () async {
        var calls = 0;
        final client = MockClient((_) async {
          calls++;
          if (calls == 1) {
            // Outlives the injected timeout below.
            await Future<void>.delayed(const Duration(milliseconds: 400));
          }
          return Response('', 200);
        });

        final service = SnapshotValidationService(
          configService: configService,
          clientFactory: () => client,
          retryDelays: noDelays(3),
          headTimeout: const Duration(milliseconds: 100),
        );

        expect(
          await service.validateSnapshotItems([_FakeSnapshotItem()]),
          hasLength(1),
        );
        expect(calls, 2);
      });

      /// `Future.timeout` abandons the response but does not cancel the
      /// request behind it. Left pending, four attempts across three
      /// concurrent validations is up to twelve requests outstanding against a
      /// gateway already too slow to answer one - and on the web, where
      /// browsers cap connections per host at around six, those would crowd
      /// out the reads sync makes to the same gateway next. Closing the
      /// client is what cancels them.
      test('cancels a timed-out probe before the next one', () async {
        final clients = <_CloseTrackingClient>[];

        final service = SnapshotValidationService(
          configService: configService,
          clientFactory: () {
            // Checked here rather than only at the end: asserting after the
            // fact would still pass if a regression started the next probe
            // while the abandoned one was still open, which is the thing
            // being prevented.
            if (clients.isNotEmpty) {
              expect(clients.last.closed, isTrue,
                  reason: 'the previous probe must be cancelled before the '
                      'next one is started');
            }
            final client = _CloseTrackingClient(
              MockClient((_) async {
                // The first probe never answers; the second does.
                if (clients.length == 1) {
                  await Completer<Response>().future;
                }
                return Response('', 200);
              }),
            );
            clients.add(client);
            return client;
          },
          retryDelays: noDelays(3),
          headTimeout: const Duration(milliseconds: 100),
        );

        expect(
          await service.validateSnapshotItems([_FakeSnapshotItem()]),
          hasLength(1),
        );
        expect(clients, hasLength(2), reason: 'the probe was retried');
        expect(clients.first.closed, isTrue,
            reason: 'the abandoned request must be cancelled, not left '
                'pending against a struggling gateway');
      });

      /// The band this change exists for. Measured against turbo-gateway,
      /// healthy answers arrived at 5.85s and 6.08s - a gateway that had to
      /// fetch before it could answer, not a failure. The old 5s cutoff threw
      /// those away and re-walked the whole block range instead.
      test('accepts an answer that is slow but arrives within the timeout',
          () async {
        var calls = 0;
        final client = MockClient((_) async {
          calls++;
          // Comfortably slow, but inside the budget.
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return Response('', 200);
        });

        final service = SnapshotValidationService(
          configService: configService,
          clientFactory: () => client,
          retryDelays: noDelays(3),
          headTimeout: const Duration(seconds: 1),
        );

        expect(
          await service.validateSnapshotItems([_FakeSnapshotItem()]),
          hasLength(1),
          reason: 'a slow gateway is not an unavailable snapshot',
        );
        expect(calls, 1, reason: 'no retry needed when the answer arrives');
      });
    });
  });
}
