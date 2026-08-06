import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/pages/raw_transaction_view/raw_transaction_content.dart';
import 'package:ardrive/pages/raw_transaction_view/raw_transaction_view_cubit.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/arweave/data_gateway_fallback.dart';
import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

import '../../test_utils/mocks.dart';

class MockDataGatewayFallback extends Mock implements DataGatewayFallback {}

/// How `/view/{txId}` gets its bytes, and what it refuses to do to get them.
void main() {
  const txId = 'j48SFG4GgnFej4tCqKU2iUgI4alFArg_8o8pVLiGujI';

  late MockArweaveService arweave;
  late MockDataGatewayFallback gatewayFallback;
  late Arweave client;

  Uint8List ascii(String text) => Uint8List.fromList(utf8.encode(text));

  InfoOfTransactionToBePinned$Query$Transaction description({
    required String size,
    String? type,
  }) =>
      InfoOfTransactionToBePinned$Query$Transaction.fromJson(<String, dynamic>{
        'owner': <String, dynamic>{
          'address': 'Zvp8dEkO3nQ2wX9yV8uT7sR6qP5oN4mL3kJ2iH1gF0e',
        },
        'tags': <Map<String, dynamic>>[],
        'data': <String, dynamic>{'size': size, 'type': type},
      });

  RawTransactionViewCubit build({String? name, String? contentType}) =>
      RawTransactionViewCubit(
        txId: txId,
        arweave: arweave,
        nameHint: name,
        contentTypeHint: contentType,
      );

  setUpAll(() {
    registerFallbackValue(MockArweave());
  });

  setUp(() {
    arweave = MockArweaveService();
    gatewayFallback = MockDataGatewayFallback();
    client = Arweave(
      api: ArweaveApi(gatewayUrl: Uri.parse('https://arweave.net')),
    );

    when(() => arweave.client).thenReturn(client);
    when(() => arweave.gatewayFallback).thenReturn(gatewayFallback);
    when(() => arweave.getInfoOfTxToBePinned(any()))
        .thenAnswer((_) async => null);
  });

  test('fetches through the gateway-fallback waterfall, not one gateway',
      () async {
    when(() => gatewayFallback.fetchData(any(), any())).thenAnswer(
      (_) async => http.Response.bytes(
        ascii('a plain little file'),
        200,
        headers: const {'content-type': 'text/plain'},
      ),
    );

    final cubit = build();
    await cubit.currentLoad;

    // The waterfall - primary → GAR → arweave.net - is the only fetch path.
    // A blackholed primary gateway must not be the whole story for a link
    // somebody was sent.
    verify(() => gatewayFallback.fetchData(txId, client)).called(1);

    final state = cubit.state;

    expect(state, isA<RawTransactionReady>());
    expect(
      (state as RawTransactionReady).presentation.renderer,
      RawTransactionRenderer.text,
    );

    await cubit.close();
  });

  test('builds the sandbox URL from the configured gateway', () async {
    when(() => arweave.client).thenReturn(
      Arweave(
        api: ArweaveApi(gatewayUrl: Uri.parse('https://turbo-gateway.com')),
      ),
    );
    when(() => gatewayFallback.fetchData(any(), any())).thenAnswer(
      (_) async => http.Response.bytes(ascii('hello'), 200),
    );

    final cubit = build();
    await cubit.currentLoad;

    expect(
      (cubit.state as RawTransactionReady).sandboxUrl,
      'https://r6hrefdoa2bhcxuprnbkrjjwrfearynjiublqp7sr4uvjoegxiza'
      '.turbo-gateway.com/$txId',
    );

    await cubit.close();
  });

  test('a string that is not a transaction id fetches nothing at all',
      () async {
    final cubit = RawTransactionViewCubit(
      txId: 'evil.example.com/../../etc/passwd',
      arweave: arweave,
    );
    await cubit.currentLoad;

    expect(cubit.state, isA<RawTransactionLinkDamaged>());
    verifyNever(() => gatewayFallback.fetchData(any(), any()));
    verifyNever(() => arweave.getInfoOfTxToBePinned(any()));

    await cubit.close();
  });

  test('an all-gateway miss is NOT_FOUND, not a network error', () async {
    when(() => gatewayFallback.fetchData(any(), any()))
        .thenThrow(TransactionNotFound(txId));

    final cubit = build();
    await cubit.currentLoad;

    expect(cubit.state, isA<RawTransactionNotFound>());

    await cubit.close();
  });

  test('a gateway failure is a network error, with a retry', () async {
    when(() => gatewayFallback.fetchData(any(), any()))
        .thenThrow(Exception('all gateways failed'));

    final cubit = build();
    await cubit.currentLoad;

    expect(cubit.state, isA<RawTransactionLoadFailure>());

    when(() => gatewayFallback.fetchData(any(), any())).thenAnswer(
      (_) async => http.Response.bytes(ascii('recovered'), 200),
    );

    await cubit.retry();

    expect(cubit.state, isA<RawTransactionReady>());

    await cubit.close();
  });

  test('media is never buffered', () async {
    final cubit = build(contentType: 'video/mp4', name: 'talk.mp4');
    await cubit.currentLoad;

    final state = cubit.state as RawTransactionReady;

    expect(state.presentation.renderer, RawTransactionRenderer.media);
    expect(state.bytes, isNull);
    verifyNever(() => gatewayFallback.fetchData(any(), any()));

    await cubit.close();
  });

  test('a transaction bigger than the inline budget is never fetched',
      () async {
    when(() => arweave.getInfoOfTxToBePinned(any())).thenAnswer(
      (_) async => description(
        size: '${rawTransactionInlineMaxBytes + 1}',
        type: 'application/pdf',
      ),
    );

    final cubit = build();
    await cubit.currentLoad;

    final state = cubit.state as RawTransactionReady;

    expect(state.isOversized, isTrue);
    expect(state.presentation.renderer, RawTransactionRenderer.downloadOnly);
    verifyNever(() => gatewayFallback.fetchData(any(), any()));

    await cubit.close();
  });

  test('the gateway\'s own Content-Type can only make the verdict stricter',
      () async {
    // The link says text, the gateway says HTML, the bytes are text. HTML wins:
    // a claim from any source may restrict, and none may unlock.
    when(() => gatewayFallback.fetchData(any(), any())).thenAnswer(
      (_) async => http.Response.bytes(
        ascii('totally harmless'),
        200,
        headers: const {'content-type': 'text/html; charset=utf-8'},
      ),
    );

    final cubit = build(contentType: 'text/plain');
    await cubit.currentLoad;

    expect(
      (cubit.state as RawTransactionReady).presentation.renderer,
      RawTransactionRenderer.sandboxed,
    );

    await cubit.close();
  });

  test('GraphQL being unavailable costs a size chip, never the page', () async {
    when(() => arweave.getInfoOfTxToBePinned(any()))
        .thenThrow(Exception('graphql is down'));
    when(() => gatewayFallback.fetchData(any(), any())).thenAnswer(
      (_) async => http.Response.bytes(ascii('still here'), 200),
    );

    final cubit = build();
    await cubit.currentLoad;

    final state = cubit.state as RawTransactionReady;

    expect(state.presentation.renderer, RawTransactionRenderer.text);
    expect(state.size, isNull);

    await cubit.close();
  });

  test('a name from a transaction tag cannot carry a path or a newline',
      () async {
    when(() => arweave.getInfoOfTxToBePinned(any())).thenAnswer(
      (_) async =>
          InfoOfTransactionToBePinned$Query$Transaction.fromJson(<String, dynamic>{
        'owner': <String, dynamic>{
          'address': 'Zvp8dEkO3nQ2wX9yV8uT7sR6qP5oN4mL3kJ2iH1gF0e',
        },
        'tags': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'File-Name',
            'value': '../../etc/passwd\nSaved',
          },
        ],
        'data': <String, dynamic>{'size': '9', 'type': 'text/plain'},
      }),
    );
    when(() => gatewayFallback.fetchData(any(), any())).thenAnswer(
      (_) async => http.Response.bytes(ascii('some text'), 200),
    );

    final cubit = build();
    await cubit.currentLoad;

    final name = (cubit.state as RawTransactionReady).name;

    expect(name, isNotNull);
    expect(name, isNot(contains('/')));
    expect(name, isNot(contains('\n')));

    await cubit.close();
  });
}
