import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/config/selected_gateway.dart';
import 'package:ardrive/utils/graphql_retry.dart';
import 'package:ardrive/utils/internet_checker.dart';
import 'package:artemis/artemis.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/mocks.dart';

class _MockArtemisClient extends Mock implements ArtemisClient {}

class _MockInternetChecker extends Mock implements InternetChecker {}

typedef _Tx
    = InfoOfTransactionsToBePinned$Query$TransactionConnection$TransactionEdge$Transaction;

/// Answers every query with [_answer], or throws what it throws, and records
/// the ids each query asked for.
class _FakeRetry extends GraphQLRetry {
  _FakeRetry(this._answer)
      : super(_MockArtemisClient(), internetChecker: _MockInternetChecker());

  final List<_Tx> Function(List<String> ids) _answer;

  final List<List<String>> askedFor = [];

  @override
  Future<GraphQLResponse<T>> execute<T, U extends JsonSerializable>(
    GraphQLQuery<T, U> query, {
    Function(Exception e)? onRetry,
    int maxAttempts = GraphQLRetry.defaultMaxAttempts,
  }) async {
    final ids = (query.variables as InfoOfTransactionsToBePinnedArguments)
        .transactionIds!;
    askedFor.add(ids);

    final data = InfoOfTransactionsToBePinned$Query()
      ..transactions =
          (InfoOfTransactionsToBePinned$Query$TransactionConnection()
            ..edges = _answer(ids)
                .map((tx) =>
                    InfoOfTransactionsToBePinned$Query$TransactionConnection$TransactionEdge()
                      ..node = tx)
                .toList());

    return GraphQLResponse<T>(data: data as T);
  }
}

_Tx _tx(String id, {required String size, String? contentType}) => _Tx()
  ..id = id
  ..owner =
      (InfoOfTransactionsToBePinned$Query$TransactionConnection$TransactionEdge$Transaction$Owner()
        ..address = 'owner')
  ..tags = [
    if (contentType != null)
      InfoOfTransactionsToBePinned$Query$TransactionConnection$TransactionEdge$Transaction$Tag()
        ..name = 'Content-Type'
        ..value = contentType,
  ]
  ..data =
      (InfoOfTransactionsToBePinned$Query$TransactionConnection$TransactionEdge$Transaction$MetaData()
        ..size = size);

/// Importing from a manifest needs each file's size and content type. The
/// gateway's index can refuse the GraphQL that asks for them (#2222); the data
/// gateway's headers must then answer instead, and a file neither can describe
/// must come back as `null`, not vanish.
void main() {
  const gateway = 'https://gateway.test';

  late List<Uri> heads;

  ArweaveService serviceWith(
    _FakeRetry retry,
    Future<http.Response> Function(http.Request) onHead,
  ) {
    final configService = MockConfigService();
    final config = MockConfig();

    when(() => configService.config).thenReturn(config);
    when(() => config.arweaveGatewayUrl).thenReturn(gateway);
    when(() => config.arweaveGatewayForDataRequest)
        .thenReturn(const SelectedGateway(label: 'test', url: gateway));

    final service = ArweaveService(
      MockArweave(),
      MockArDriveCrypto(),
      MockDriveDao(),
      configService,
      artemisClient: _MockArtemisClient(),
      httpClient: MockClient((request) {
        expect(request.method, 'HEAD');
        heads.add(request.url);
        return onHead(request);
      }),
    );

    service.graphQLRetry = retry;

    return service;
  }

  setUp(() => heads = []);

  Future<http.Response> neverAsked(http.Request _) =>
      fail('the gateway should not have been asked');

  test('GraphQL answers the whole batch and the gateway is not asked',
      () async {
    final service = serviceWith(
      _FakeRetry((ids) => [
            _tx('a', size: '10', contentType: 'text/html'),
            _tx('b', size: '20'),
          ]),
      neverAsked,
    );

    final batches = await service.getSizeAndTypeOfDataTxs(['a', 'b']).toList();

    expect(batches, hasLength(1));
    expect(batches.single['a']?.size, 10);
    expect(batches.single['a']?.contentType, 'text/html');
    expect(batches.single['b']?.size, 20);
    expect(batches.single['b']?.contentType, isNull);
  });

  test('a batch GraphQL refuses is answered from the gateway headers',
      () async {
    final service = serviceWith(
      _FakeRetry((_) => throw GraphQLException(
            'Limit for rows or bytes to read exceeded',
          )),
      (request) async => http.Response('', 200, headers: {
        'content-length': request.url.path.endsWith('/a') ? '1234' : '99',
        'content-type': 'text/css; charset=utf-8',
      }),
    );

    final batches = await service.getSizeAndTypeOfDataTxs(['a', 'b']).toList();

    expect(heads.map((u) => u.toString()),
        unorderedEquals(['$gateway/raw/a', '$gateway/raw/b']));
    expect(batches.single['a']?.size, 1234);
    expect(batches.single['b']?.size, 99);
    expect(batches.single['a']?.contentType, 'text/css',
        reason: 'parameters such as charset are not part of the type');
  });

  test('only the ids GraphQL left out are asked of the gateway', () async {
    final service = serviceWith(
      _FakeRetry((ids) => [_tx('a', size: '10')]),
      (_) async => http.Response('', 200, headers: {'content-length': '5'}),
    );

    final batches = await service.getSizeAndTypeOfDataTxs(['a', 'b']).toList();

    expect(heads.map((u) => u.path), ['/raw/b']);
    expect(batches.single['a']?.size, 10);
    expect(batches.single['b']?.size, 5);
  });

  test('an id neither source can describe is present, as null', () async {
    final service = serviceWith(
      _FakeRetry((_) => throw GraphQLException('refused')),
      (_) async => http.Response('', 404),
    );

    final batches = await service.getSizeAndTypeOfDataTxs(['a']).toList();

    expect(batches.single.containsKey('a'), isTrue);
    expect(batches.single['a'], isNull);
  });

  test('every id is yielded, batch by batch, when every batch fails',
      () async {
    final retry = _FakeRetry((_) => throw GraphQLException('refused'));
    final service = serviceWith(
      retry,
      (_) async => http.Response('', 200, headers: {'content-length': '1'}),
    );

    final ids = List.generate(12, (i) => 'tx$i');
    final batches =
        await service.getSizeAndTypeOfDataTxs(ids, batchSize: 5).toList();

    expect(retry.askedFor.map((b) => b.length), [5, 5, 2]);
    expect(batches.expand((b) => b.keys), ids);
    expect(batches.expand((b) => b.values).every((v) => v?.size == 1), isTrue);
  });
}
