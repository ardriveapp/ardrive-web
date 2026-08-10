import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/core/download_service.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/arweave/data_gateway_fallback.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';

class MockArweaveService extends Mock implements ArweaveService {}

class MockDataGatewayFallback extends Mock implements DataGatewayFallback {}

class MockArioSDK extends Mock implements ArioSDK {}

/// [DownloadService] fetched from one gateway by hand: whatever
/// `arweaveGatewayForDataRequest` happened to be, once, with no second try.
/// Everything it feeds - a manifest import, a multi-file download, the password
/// login that verifies a wallet's first transaction - therefore failed outright
/// whenever that one gateway was down, even though the data was sitting on
/// every other gateway in the network. These tests pin it to the same waterfall
/// (primary → GAR → arweave.net) the rest of the app reads data with.
void main() {
  const txId = 'pQ4rS6tU9vW1xY3zA5bC7dE0fG2hI4jK6lM8nO0pQ2r';

  final data = Uint8List.fromList([4, 8, 15, 16, 23, 42]);

  late MockArweaveService arweave;
  late MockDataGatewayFallback gatewayFallback;
  late Arweave client;

  setUp(() {
    arweave = MockArweaveService();
    gatewayFallback = MockDataGatewayFallback();
    client = Arweave(
      api: ArweaveApi(gatewayUrl: Uri.parse('https://primary.test')),
    );

    when(() => arweave.client).thenReturn(client);
    when(() => arweave.gatewayFallback).thenReturn(gatewayFallback);
  });

  test('a file download goes through the waterfall, not a single gateway',
      () async {
    when(() => gatewayFallback.fetchFileData(txId, client))
        .thenAnswer((_) async => data);

    final bytes = await DownloadService(arweave).download(txId, false);

    expect(bytes, data);

    // `fetchFileData` and not `fetchData`: this call carries whole files, and
    // `fetchData` caps a gateway attempt at five seconds of body.
    verify(() => gatewayFallback.fetchFileData(txId, client)).called(1);
    verifyNever(() => gatewayFallback.fetchData(txId, client));
  });

  test('a manifest download goes through the manifest waterfall', () async {
    when(() => gatewayFallback.fetchManifestWithFallback(txId, client))
        .thenAnswer((_) async => Response.bytes(data, 200));

    final bytes = await DownloadService(arweave).download(txId, true);

    expect(bytes, data);

    // The manifest waterfall reads `/raw/`; the ordinary one would resolve the
    // manifest to the file its index points at instead.
    verify(() => gatewayFallback.fetchManifestWithFallback(txId, client))
        .called(1);
    verifyNever(() => gatewayFallback.fetchData(txId, client));
  });

  test('a streamed download goes through the waterfall too', () async {
    when(() => gatewayFallback.downloadWithFallback(
          txId: txId,
          primaryClient: client,
        )).thenAnswer((_) async => (Stream<List<int>>.value(data), () {}));

    final stream = await DownloadService(arweave).downloadStream(txId, false);

    expect(await stream.expand((chunk) => chunk).toList(), data);
    verify(() => gatewayFallback.downloadWithFallback(
          txId: txId,
          primaryClient: client,
        )).called(1);
  });

  group('end to end, over a real waterfall', () {
    const manifestJson = '{"manifest":"arweave/paths","version":"0.2.0",'
        '"index":{"path":"ドキュメント.html"},'
        '"paths":{'
        '"ドキュメント.html":{"id":"aB1cD2eF3gH4iJ5kL6mN7oP8qR9sT0uV1wX2yZ3aB4c"},'
        '"holiday 🎉.png":'
        '{"id":"cD3eF4gH5iJ6kL7mN8oP9qR0sT1uV2wX3yZ4aB5cD6e"}}}';

    late MockArioSDK arioSDK;
    late List<BaseRequest> requests;

    // The waterfall as production builds it, with only the socket faked.
    void useRealWaterfall(Future<Response> Function(Request) handler) {
      when(() => arweave.gatewayFallback).thenReturn(
        DataGatewayFallback(
          arioSDK: arioSDK,
          clientFactory: () => MockClient((request) {
            requests.add(request);

            return handler(request);
          }),
        ),
      );
    }

    setUp(() {
      arioSDK = MockArioSDK();
      requests = [];

      // No GAR gateways, so the waterfall is exactly primary → arweave.net.
      when(() => arioSDK.getGateways()).thenAnswer((_) async => <Gateway>[]);
    });

    test('a dead primary gateway still yields the manifest, bytes intact',
        () async {
      useRealWaterfall((request) async {
        if (request.url.host == 'primary.test') {
          return Response('', 503);
        }

        return Response.bytes(utf8.encode(manifestJson), 200);
      });

      final bytes = await DownloadService(arweave).download(txId, true);

      expect(
        requests.map((request) => request.url).toList(),
        [
          Uri.parse('https://primary.test/raw/$txId'),
          Uri.parse('https://arweave.net/raw/$txId'),
        ],
      );

      // Not just "some bytes came back": the manifest names files with an
      // emoji and with CJK characters, which is what the latin1 round trip in
      // the old manifest fetch could not carry.
      expect(utf8.decode(bytes), manifestJson);
    });

    test('a dead primary gateway still yields the file, whole and uncapped',
        () async {
      useRealWaterfall((request) async {
        if (request.url.host == 'primary.test') {
          return Response('', 502);
        }

        return Response.bytes(data, 200);
      });

      final bytes = await DownloadService(arweave).download(txId, false);

      expect(
        requests.map((request) => request.url.host).toList(),
        ['primary.test', 'arweave.net'],
      );
      expect(bytes, data);

      // No `Range`: a file download wants the whole transaction, however big it
      // is. Only the bounded thumbnail fetch caps what it asks for.
      expect(
        requests.every((request) => !request.headers.containsKey('Range')),
        isTrue,
      );
    });
  });
}
