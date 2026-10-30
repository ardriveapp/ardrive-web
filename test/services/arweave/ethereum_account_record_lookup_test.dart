import 'dart:convert';

import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/config/selected_gateway.dart';
import 'package:ardrive/services/ethereum/ethereum_account.dart';
import 'package:artemis/artemis.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/mocks.dart';

class _MockArtemisClient extends Mock implements ArtemisClient {}

const _configured = 'https://configured.example';

http.Response _records(List<Map<String, Object>> edges) => http.Response(
      jsonEncode({
        'data': {
          'transactions': {'edges': edges}
        }
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

Map<String, Object> _edge(String id, [Map<String, String> tags = const {}]) => {
      'node': {
        'id': id,
        'tags': [
          for (final t in tags.entries) {'name': t.key, 'value': t.value}
        ],
      }
    };

/// Which endpoints a MetaMask account's record is read on, and when "no
/// record" may be the answer.
void main() {
  late List<String> asked;

  ArweaveService serviceAnswering(
    Map<String, http.Response Function()> byHost, {
    String gateway = _configured,
  }) {
    final configService = MockConfigService();
    final config = MockConfig();
    when(() => configService.config).thenReturn(config);
    when(() => config.arweaveGatewayUrl).thenReturn(gateway);
    when(() => config.arweaveGatewayForDataRequest)
        .thenReturn(SelectedGateway(label: 'test', url: gateway));

    final service = ArweaveService(
      MockArweave(),
      MockArDriveCrypto(),
      MockDriveDao(),
      configService,
    );
    service.accountLookupHttpClient = MockClient((request) async {
      asked.add(request.url.host);
      final answer = byHost[request.url.host];
      if (answer == null) throw Exception('unreachable ${request.url.host}');
      return answer();
    });
    return service;
  }

  setUp(() => asked = []);

  test(
      'none on the configured endpoint and turbo-gateway.com: no record, and '
      'nothing else is asked', () async {
    final service = serviceAnswering({
      'configured.example': () => _records([]),
      'turbo-gateway.com': () => _records([]),
    });

    expect(await service.findEthereumAccountRecord('auth'), isNull);
    expect(asked.toSet(), {'configured.example', 'turbo-gateway.com'});
  });

  test('a marker only the turbo-gateway index has is found', () async {
    final service = serviceAnswering({
      'configured.example': () => _records([]),
      'turbo-gateway.com': () => _records([
            _edge('marker', {
              'ArDrive-Account-Version': '2',
              'ArDrive-Account-Address': 'arweave-address',
            })
          ]),
    });

    final found = await service.findEthereumAccountRecord('auth');
    expect(found, isA<EthereumV2Marker>());
    expect((found as EthereumV2Marker).accountAddress, 'arweave-address');
  });

  test('turbo-gateway.com blocked: ardrive.net answers for the same index',
      () async {
    final service = serviceAnswering({
      'configured.example': () => _records([]),
      'ardrive.net': () => _records([_edge('v1')]),
    });

    expect(await service.findEthereumAccountRecord('auth'),
        isA<EthereumV1Record>());
    expect(asked, contains('ardrive.net'));
  });

  test('a 429 from the configured endpoint is a failure, never no record',
      () async {
    final service = serviceAnswering({
      'configured.example': () => http.Response('slow down', 429),
      'turbo-gateway.com': () => _records([]),
    });

    await expectLater(
        service.findEthereumAccountRecord('auth'), throwsA(anything));
  });

  test('the index unreachable on both domains is a failure', () async {
    final service = serviceAnswering({
      'configured.example': () => _records([]),
      'turbo-gateway.com': () => http.Response('bad gateway', 502),
    });

    await expectLater(service.findEthereumAccountRecord('auth'),
        throwsA(isA<AccountLookupUnavailable>()));
  });

  test('a configured turbo-gateway.com is asked once, as the index', () async {
    final service = serviceAnswering({
      'turbo-gateway.com': () => _records([]),
    }, gateway: 'https://turbo-gateway.com');

    expect(await service.findEthereumAccountRecord('auth'), isNull);
    expect(asked, ['turbo-gateway.com']);
  });

  test('a lookup that fails is retried on its own endpoint, not Goldsky', () {
    final retry = ArweaveService.accountLookupRetry(
        _MockArtemisClient(), 'https://turbo-gateway.com/graphql');
    expect(retry.fallbackGraphqlUrl, 'https://turbo-gateway.com/graphql');
  });

  test('never Goldsky or arweave.net', () async {
    final service = serviceAnswering({
      'configured.example': () => http.Response('down', 503),
    });

    await expectLater(
        service.findEthereumAccountRecord('auth'), throwsA(anything));
    expect(asked, isNot(contains('arweave-search.goldsky.com')));
    expect(asked, isNot(contains('arweave.net')));
  });
}
