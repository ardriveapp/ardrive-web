import 'dart:convert';

import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/arweave/data_gateway_fallback.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';

class MockArioSDK extends Mock implements ArioSDK {}

/// `fetchManifestWithFallback` — a manifest's own bytes, from `/raw/`.
///
/// A manifest is UTF-8 JSON whose `paths` map is keyed by file names, so any
/// drive holding a file with an emoji or a CJK character in its name has a
/// manifest that is not Latin-1. This used to fetch the manifest as text and
/// hand it back as `Response(String, int)`, which encodes with latin1 - what
/// `package:http` falls back to when no `content-type` charset says otherwise -
/// and throws on the first character it cannot represent. The throw landed in
/// the waterfall's `catch`, counted as that gateway failing, and reached the
/// user as "all gateways failed" once every gateway had returned the same
/// perfectly good manifest.
void main() {
  const txId = 'kL2mN8pQ4rS6tU9vW1xY3zA5bC7dE0fG2hI4jK6lM8n';

  // The shape a real manifest has: names in the keys, ids in the values.
  const manifestJson = '{"manifest":"arweave/paths","version":"0.2.0",'
      '"index":{"path":"ドキュメント.html"},'
      '"paths":{'
      '"ドキュメント.html":{"id":"aB1cD2eF3gH4iJ5kL6mN7oP8qR9sT0uV1wX2yZ3aB4c"},'
      '"holiday 🎉.png":'
      '{"id":"cD3eF4gH5iJ6kL7mN8oP9qR0sT1uV2wX3yZ4aB5cD6e"}}}';

  late MockArioSDK arioSDK;

  setUp(() {
    arioSDK = MockArioSDK();

    // No GAR gateways, so the waterfall is exactly primary → arweave.net.
    when(() => arioSDK.getGateways()).thenAnswer((_) async => <Gateway>[]);
  });

  Arweave gateway(String host) =>
      Arweave(api: ArweaveApi(gatewayUrl: Uri.parse('https://$host')));

  DataGatewayFallback build(MockClientHandler handler) => DataGatewayFallback(
        arioSDK: arioSDK,
        clientFactory: () => MockClient(handler),
      );

  test('a manifest whose file names are not Latin-1 survives the fetch',
      () async {
    final requests = <BaseRequest>[];

    final fallback = build((request) async {
      requests.add(request);

      return Response.bytes(
        utf8.encode(manifestJson),
        200,
        headers: const {'content-type': 'application/json'},
      );
    });

    final response = await fallback.fetchManifestWithFallback(
      txId,
      gateway('primary.test'),
    );

    expect(utf8.decode(response.bodyBytes), manifestJson);
    expect(requests.single.url, Uri.parse('https://primary.test/raw/$txId'));
  });

  test('a dead primary falls through, and the fallback manifest survives too',
      () async {
    final hosts = <String>[];

    final fallback = build((request) async {
      hosts.add(request.url.host);

      if (request.url.host == 'primary.test') {
        return Response('', 503);
      }

      return Response.bytes(utf8.encode(manifestJson), 200);
    });

    final response = await fallback.fetchManifestWithFallback(
      txId,
      gateway('primary.test'),
    );

    expect(hosts, ['primary.test', 'arweave.net']);
    expect(utf8.decode(response.bodyBytes), manifestJson);
  });

  test('a manifest no gateway has is a missing transaction, not a failure',
      () async {
    final fallback = build((request) async => Response('', 404));

    await expectLater(
      fallback.fetchManifestWithFallback(txId, gateway('primary.test')),
      throwsA(isA<TransactionNotFound>()),
    );
  });
}
