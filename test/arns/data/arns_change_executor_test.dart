import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/arns/data/arns_change_executor.dart';
import 'package:ardrive/arns/data/turbo_arns_action_client.dart';
import 'package:ardrive/arns/domain/arns_action.dart';
import 'package:ardrive/arns/domain/arns_names.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';

const _owner = '6eV7bK3bQJdd7Q44doWqAbnBCWNQRhB1HwCDGWf8Qe3V';
const _antId = 'EH9PsyfwJBk9KLMpZ2C5nUjWQfXsNTHaUzTqFa4BpbQj';
const _txId = 'FWswWiH1FMFnuzLFzpqzdgxOBlMS8L7DiP5MxUnWODE';

class _MockArioSDK extends Mock implements ArioSDK {}

class _Owner implements ArNSOwnerSigner {
  _Owner({this.rejectMessage = false, this.rejectTransaction = false});

  final bool rejectMessage;
  final bool rejectTransaction;
  int transactions = 0;

  @override
  String get address => _owner;

  @override
  Future<Uint8List> signMessage(Uint8List message) async {
    if (rejectMessage) throw Exception('User rejected the request.');
    return Uint8List.fromList(List.filled(64, 7));
  }

  @override
  Future<String> signTransaction(String transactionBase64) async {
    transactions++;
    if (rejectTransaction) throw Exception('User rejected the request.');
    return 'signed';
  }
}

class _Payer implements ArNSPayerSigner {
  @override
  Future<Map<String, String>> signedRequestHeaders(String nonce) async =>
      {'x-nonce': nonce, 'x-signature': 's', 'x-public-key': 'k'};
}

const _change = ArNSSetRecord(
  antId: _antId,
  undername: 'blog',
  transactionId: _txId,
  ttlSeconds: 300,
);

ArNSManagedName _name(ArNSRole role) => ArNSManagedName(
      name: 'acme',
      processId: _antId,
      role: role,
      type: ArNSNameType.permabuy,
      endTimestamp: null,
      undernameLimit: 10,
      records: const [],
    );

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

void main() {
  late List<http.Request> requests;
  late _MockArioSDK sdk;
  late List<ArNSCommitStep> steps;

  ArNSChangeExecutor executor(
    Future<http.Response> Function(http.Request) handler,
  ) {
    var n = 0;
    return ArNSChangeExecutor(
      client: TurboArNSActionClient(
        paymentUrl: () => 'https://payment.example',
        client: MockClient((request) {
          requests.add(request);
          return handler(request);
        }),
        newNonce: () => 'nonce-${n++}',
        delay: (_) async {},
      ),
      arioSDK: sdk,
    );
  }

  bool isCreate(http.Request r) =>
      r.method == 'POST' && r.url.path.endsWith('/set-record');

  setUp(() {
    requests = [];
    sdk = _MockArioSDK();
    steps = [];
  });

  Future<ArNSChangeFailure?> run(
    ArNSChangeExecutor executor, {
    ArNSRole role = ArNSRole.owner,
    _Owner? owner,
  }) async {
    try {
      await executor.execute(
        name: _name(role),
        change: _change,
        owner: owner ?? _Owner(),
        payer: _Payer(),
        onStep: steps.add,
      );
      return null;
    } on ArNSChangeFailure catch (failure) {
      return failure;
    }
  }

  test('a completed action takes one create and one approval', () async {
    final failure = await run(executor((r) async => _json({
          'nonce': 'a1',
          'action': 'set-record',
          'status': 'completed',
        })));

    expect(failure, isNull);
    expect(requests.where(isCreate), hasLength(1));
    expect(steps, [ArNSCommitStep.approve, ArNSCommitStep.working]);
  });

  test('awaiting-signature asks the wallet again and signs once', () async {
    final owner = _Owner();
    final failure = await run(
      executor((r) async {
        if (isCreate(r)) {
          return _json({
            'nonce': 'a1',
            'action': 'set-record',
            'status': 'awaiting-signature',
            'transaction': 'dHg=',
          });
        }
        return _json({
          'nonce': 'a1',
          'action': 'set-record',
          'status': 'completed',
        });
      }),
      owner: owner,
    );

    expect(failure, isNull);
    expect(owner.transactions, 1);
    expect(steps, [ArNSCommitStep.approve, ArNSCommitStep.approveTransaction]);
    expect(requests.map((r) => r.url.path), [
      '/v1/arns/actions/set-record',
      '/v1/arns/actions/a1/sign',
    ]);
  });

  test('rejecting the proof prompt charges nothing and sends nothing',
      () async {
    final failure = await run(
      executor((r) async => _json({})),
      owner: _Owner(rejectMessage: true),
    );

    expect(failure?.kind, ArNSFailureKind.rejected);
    expect(requests, isEmpty);
  });

  test('a 402 is not enough credits', () async {
    final failure = await run(
      executor((r) async => _json({'error': 'Insufficient balance'}, 402)),
    );

    expect(failure?.kind, ArNSFailureKind.insufficientCredits);
  });

  test('a lost response after the request went out is never retried', () async {
    final failure = await run(executor((r) async {
      throw http.ClientException('Connection closed');
    }));

    expect(failure?.kind, ArNSFailureKind.lostAfterCreate);
    expect(requests.where(isCreate), hasLength(1));
  });

  test('rejecting the second prompt lets the action expire with a refund',
      () async {
    final failure = await run(
      executor((r) async => _json({
            'nonce': 'a1',
            'action': 'set-record',
            'status': 'awaiting-signature',
            'transaction': 'dHg=',
          })),
      owner: _Owner(rejectTransaction: true),
    );

    expect(failure?.kind, ArNSFailureKind.expired);
    expect(requests.where(isCreate), hasLength(1));
  });

  test('an expired sign says whether the credits came back', () async {
    final failure = await run(executor((r) async {
      if (isCreate(r)) {
        return _json({
          'nonce': 'a1',
          'action': 'set-record',
          'status': 'awaiting-signature',
          'transaction': 'dHg=',
        });
      }
      return _json(
        {'error': 'Action expired', 'refunded': true},
        409,
      );
    }));

    expect(failure?.kind, ArNSFailureKind.expired);
    expect(failure?.refunded, isTrue);
    expect(requests.where(isCreate), hasLength(1));
  });

  test('Turbo refusing before the action exists charges nothing', () async {
    final failure = await run(
      executor((r) async => _json({'error': 'Invalid owner proof'}, 400)),
    );

    expect(failure?.kind, ArNSFailureKind.failed);
  });

  test('a name managed for its owner is written by the wallet itself',
      () async {
    when(() => sdk.setRecordAsController(
          processId: _antId,
          undername: 'blog',
          transactionId: _txId,
          ttlSeconds: 300,
        )).thenAnswer((_) async => 'sig');

    final failure =
        await run(executor((r) async => _json({})), role: ArNSRole.controller);

    expect(failure, isNull);
    expect(requests, isEmpty, reason: 'Turbo rejects a controller proof');
    verify(() => sdk.setRecordAsController(
          processId: _antId,
          undername: 'blog',
          transactionId: _txId,
          ttlSeconds: 300,
        )).called(1);
  });

  test('a controller rejecting its own transaction is a rejection', () async {
    when(() => sdk.setRecordAsController(
          processId: any(named: 'processId'),
          undername: any(named: 'undername'),
          transactionId: any(named: 'transactionId'),
          ttlSeconds: any(named: 'ttlSeconds'),
        )).thenThrow(Exception('User rejected'));

    final failure =
        await run(executor((r) async => _json({})), role: ArNSRole.controller);

    expect(failure?.kind, ArNSFailureKind.rejected);
  });
}
