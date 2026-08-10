import 'dart:typed_data';

import 'package:ardrive/services/arweave/data_gateway_fallback.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';

class MockArioSDK extends Mock implements ArioSDK {}

/// `fetchDataAtMost` — the fetch for data whose id came out of somebody else's
/// link.
///
/// `fetchData` hands back a fully buffered [Response], so a caller that only
/// wants a 512 KiB thumbnail has already paid for a 5 GB transaction by the
/// time it can measure one. The recipient's share page fetches whatever
/// transaction the link's `thn` field names, automatically, on paint. The
/// bound therefore has to travel with the request rather than run on the
/// answer.
void main() {
  const txId = 'nS7hxbLQmk3W1o9zX2cV4bN5mL6kJ7hG8fD9sA0qWeR';
  const cap = 1024;

  late MockArioSDK arioSDK;

  setUp(() {
    arioSDK = MockArioSDK();

    // No GAR gateways, so the waterfall is exactly primary → arweave.net.
    when(() => arioSDK.getGateways()).thenAnswer((_) async => <Gateway>[]);
  });

  Arweave gateway(String host) =>
      Arweave(api: ArweaveApi(gatewayUrl: Uri.parse('https://$host')));

  DataGatewayFallback build(MockClientStreamHandler handler) =>
      DataGatewayFallback(
        arioSDK: arioSDK,
        clientFactory: () => MockClient.streaming(handler),
      );

  test('asks for no more than the cap, and returns what fits', () async {
    final requests = <BaseRequest>[];

    final fallback = build((request, _) async {
      requests.add(request);

      return StreamedResponse(
        Stream<List<int>>.value(<int>[1, 2, 3]),
        206,
        contentLength: 3,
        headers: const {'content-range': 'bytes 0-2/3'},
      );
    });

    final bytes = await fallback.fetchDataAtMost(
      txId,
      gateway('primary.test'),
      maxBytes: cap,
    );

    expect(bytes, Uint8List.fromList([1, 2, 3]));
    expect(requests.single.url, Uri.parse('https://primary.test/$txId'));
    expect(requests.single.headers['Range'], 'bytes=0-$cap');
  });

  test('a transaction that declares more than the cap costs no body at all',
      () async {
    var bodyWasRead = false;

    // An `async*` body does not run until something listens, so this flag is a
    // faithful report of whether a byte was ever pulled.
    Stream<List<int>> hugeBody() async* {
      bodyWasRead = true;

      yield List<int>.filled(cap * 8, 0);
    }

    final fallback = build((request, _) async => StreamedResponse(
          hugeBody(),
          200,
          contentLength: cap * 8,
        ));

    final bytes = await fallback.fetchDataAtMost(
      txId,
      gateway('primary.test'),
      maxBytes: cap,
    );

    expect(bytes, isNull);
    expect(bodyWasRead, isFalse,
        reason: 'the gateway said how big it was before sending it');
  });

  test('a gateway that ignores the range and declares nothing is cut off',
      () async {
    // arweave.net answers a `Range` request with `200 OK` and the whole body
    // (measured 2026-08-05, redesign plan §3.2). A cap that is only a check on
    // what came back would be no cap at all against that.
    var bytesPulled = 0;

    Stream<List<int>> unboundedBody() async* {
      for (var i = 0; i < 1000; i++) {
        bytesPulled += 512;

        yield List<int>.filled(512, 7);
      }
    }

    final fallback = build(
      (request, _) async => StreamedResponse(unboundedBody(), 200),
    );

    final bytes = await fallback.fetchDataAtMost(
      txId,
      gateway('primary.test'),
      maxBytes: cap,
    );

    expect(bytes, isNull);
    expect(bytesPulled, lessThanOrEqualTo(cap + 512),
        reason: 'the read stopped at the first chunk that passed the cap, '
            'instead of following the body to its end');
  });

  test('a dead primary gateway falls through, as it does for every other fetch',
      () async {
    final hosts = <String>[];

    final fallback = build((request, _) async {
      hosts.add(request.url.host);

      if (request.url.host == 'primary.test') {
        return StreamedResponse(const Stream<List<int>>.empty(), 500);
      }

      return StreamedResponse(
        Stream<List<int>>.value(<int>[9]),
        200,
        contentLength: 1,
      );
    });

    final bytes = await fallback.fetchDataAtMost(
      txId,
      gateway('primary.test'),
      maxBytes: cap,
    );

    expect(hosts, ['primary.test', 'arweave.net']);
    expect(bytes, Uint8List.fromList([9]));
  });

  test('every gateway failing is an error, not an empty thumbnail', () async {
    final fallback = build(
      (request, _) async => throw Exception('connection refused'),
    );

    await expectLater(
      fallback.fetchDataAtMost(txId, gateway('primary.test'), maxBytes: cap),
      throwsA(isA<Exception>()),
    );
  });
}
