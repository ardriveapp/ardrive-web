import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/arns/data/turbo_arns_action_client.dart';
import 'package:ardrive/arns/domain/arns_action.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _owner = '6eV7bK3bQJdd7Q44doWqAbnBCWNQRhB1HwCDGWf8Qe3V';
// base64url of the 32 bytes bs58 decodes the address to (checked with bs58).
const _ownerKeyB64Url = 'U-S2eB9McpCmvlTx0fOqDhROa8Qk5582XPIJL3ZEhkw';
const _antId = 'EH9PsyfwJBk9KLMpZ2C5nUjWQfXsNTHaUzTqFa4BpbQj';
const _txId = 'FWswWiH1FMFnuzLFzpqzdgxOBlMS8L7DiP5MxUnWODE';

class _FakeOwner implements ArNSOwnerSigner {
  final messages = <Uint8List>[];
  final transactions = <String>[];

  @override
  String get address => _owner;

  @override
  Future<Uint8List> signMessage(Uint8List message) async {
    messages.add(message);
    return Uint8List.fromList(List.filled(64, 7));
  }

  @override
  Future<String> signTransaction(String transactionBase64) async {
    transactions.add(transactionBase64);
    return 'signed:$transactionBase64';
  }
}

class _FakePayer implements ArNSPayerSigner {
  final nonces = <String>[];

  @override
  Future<Map<String, String>> signedRequestHeaders(String nonce) async {
    nonces.add(nonce);
    return {
      'x-nonce': nonce,
      'x-signature': 'payer-signature',
      'x-public-key': 'payer-owner',
    };
  }
}

const _set = ArNSSetRecord(
  antId: _antId,
  undername: 'blog',
  transactionId: _txId,
  ttlSeconds: 300,
);

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

void main() {
  late List<http.Request> requests;
  late _FakeOwner owner;
  late _FakePayer payer;
  late int nonceCount;

  TurboArNSActionClient client(
    Future<http.Response> Function(http.Request) handler,
  ) {
    return TurboArNSActionClient(
      paymentUrl: () => 'https://payment.example/',
      client: MockClient((request) {
        requests.add(request);
        return handler(request);
      }),
      newNonce: () => 'nonce-${nonceCount++}',
      delay: (_) async {},
    );
  }

  setUp(() {
    requests = [];
    owner = _FakeOwner();
    payer = _FakePayer();
    nonceCount = 0;
  });

  group('owner proof', () {
    test('set-record message is newline-joined fields', () {
      expect(
        TurboArNSActionClient.ownerProofMessage(_set),
        'arns\nset-record\n$_antId\nblog\n$_txId\n300',
      );
    });

    test('remove-record message carries only the ANT and undername', () {
      expect(
        TurboArNSActionClient.ownerProofMessage(
          const ArNSRemoveRecord(antId: _antId, undername: 'blog'),
        ),
        'arns\nremove-record\n$_antId\nblog',
      );
    });

    test('signs message + nonce as UTF-8 and builds the x-owner headers',
        () async {
      final headers = await TurboArNSActionClient.ownerProofHeaders(
        owner,
        'arns\nremove-record\n$_antId\n@',
        'proof-nonce',
      );

      expect(
        utf8.decode(owner.messages.single),
        'arns\nremove-record\n$_antId\n@proof-nonce',
      );
      expect(headers, {
        'x-owner-public-key': _ownerKeyB64Url,
        'x-owner-nonce': 'proof-nonce',
        'x-owner-signature':
            base64Url.encode(List.filled(64, 7)).replaceAll('=', ''),
        'x-owner-signature-type': '4',
      });
    });
  });

  test('price reads wincQty from the unauthenticated price route', () async {
    final c = client((_) async => _json({
          'action': 'set-record',
          'wincQty': '123456789',
        }));

    expect(await c.price(ArNSRecordAction.setRecord), BigInt.from(123456789));
    expect(
      requests.single.url.toString(),
      'https://payment.example/v1/arns/actions/set-record/price',
    );
    expect(requests.single.headers.containsKey('x-signature'), isFalse);
  });

  group('create', () {
    test('posts the body with payer and owner headers on separate nonces',
        () async {
      final c = client((_) async => _json({
            'nonce': 'action-1',
            'action': 'set-record',
            'status': 'completed',
            'messageId': 'sig',
          }));

      final result = await c.create(_set, payer: payer, owner: owner);

      expect(result, isA<ArNSActionCompleted>());
      final request = requests.single;
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'https://payment.example/v1/arns/actions/set-record',
      );
      expect(jsonDecode(request.body), {
        'antId': _antId,
        'transactionId': _txId,
        'undername': 'blog',
        'ttlSeconds': 300,
        'ownerAddress': _owner,
      });
      expect(request.headers['x-owner-nonce'], 'nonce-0');
      expect(request.headers['x-nonce'], 'nonce-1');
      expect(request.headers['x-signature'], 'payer-signature');
      expect(request.headers['x-public-key'], 'payer-owner');
      expect(request.headers['x-owner-public-key'], _ownerKeyB64Url);
      expect(request.headers['x-owner-signature-type'], '4');
      expect(request.headers.containsKey('x-signature-type'), isFalse);
      expect(request.headers.containsKey('x-paid-by'), isFalse);
    });

    test('names credit sharers in x-paid-by, as uploads do', () async {
      final c = client((_) async => _json({
            'nonce': 'action-1',
            'action': 'set-record',
            'status': 'completed',
          }));

      await c.create(
        _set,
        payer: payer,
        owner: owner,
        paidBy: ['sharer-1', 'sharer-2'],
      );

      expect(requests.single.headers['x-paid-by'], 'sharer-1, sharer-2');
      expect(
        (jsonDecode(requests.single.body) as Map).containsKey('paidBy'),
        isFalse,
      );
    });

    test('402 is insufficient credits', () async {
      final c = client((_) async => http.Response('Insufficient balance', 402));

      expect(
        () => c.create(_set, payer: payer, owner: owner),
        throwsA(isA<ArNSInsufficientCreditsException>()),
      );
    });

    test('an owner who rejects the proof creates nothing', () async {
      final c = client((_) async => _json({}));
      final rejecting = _RejectingOwner();

      await expectLater(
        c.create(_set, payer: payer, owner: rejecting),
        throwsA(isA<StateError>()),
      );
      expect(requests, isEmpty);
      expect(payer.nonces, isEmpty);
    });
  });

  group('run', () {
    test('completed: reports the nonce and signs nothing', () async {
      final c = client((_) async => _json({
            'nonce': 'action-1',
            'action': 'set-record',
            'status': 'completed',
            'messageId': 'sig',
          }));
      final seen = <String>[];

      final done = await c.run(
        _set,
        payer: payer,
        owner: owner,
        onNonce: (created) => seen.add(created.nonce),
      );

      expect(done.messageId, 'sig');
      expect(seen, ['action-1']);
      expect(owner.transactions, isEmpty);
      expect(requests, hasLength(1));
    });

    test('awaiting-signature: nonce first, then the bytes signed as given',
        () async {
      final events = <String>[];
      final c = client((request) async {
        if (request.url.path.endsWith('/sign')) {
          events.add('sign');
          return _json({
            'nonce': 'action-1',
            'action': 'set-record',
            'status': 'completed',
            'messageId': 'sig',
          });
        }
        return _json({
          'nonce': 'action-1',
          'action': 'set-record',
          'status': 'awaiting-signature',
          'transaction': 'dHgtYnl0ZXM=',
          'lastValidBlockHeight': 123,
        });
      });

      final done = await c.run(
        _set,
        payer: payer,
        owner: owner,
        onNonce: (created) => events.add('nonce:${created.nonce}'),
      );

      expect(done, isA<ArNSActionCompleted>());
      expect(events, ['nonce:action-1', 'sign']);
      expect(owner.transactions, ['dHgtYnl0ZXM=']);
      final sign = requests.last;
      expect(
        sign.url.toString(),
        'https://payment.example/v1/arns/actions/action-1/sign',
      );
      expect(jsonDecode(sign.body), {'transaction': 'signed:dHgtYnl0ZXM='});
      expect(sign.headers.containsKey('x-signature'), isFalse);
      expect(sign.headers.containsKey('x-owner-signature'), isFalse);
    });

    test('blockhash not found re-posts the same bytes, never re-creates',
        () async {
      var signs = 0;
      final c = client((request) async {
        if (request.url.path.endsWith('/sign')) {
          signs++;
          return signs < 3
              ? http.Response('Blockhash not found', 503)
              : _json({
                  'nonce': 'action-1',
                  'action': 'set-record',
                  'status': 'completed',
                });
        }
        return _json({
          'nonce': 'action-1',
          'action': 'set-record',
          'status': 'awaiting-signature',
          'transaction': 'dHg=',
        });
      });

      await c.run(_set, payer: payer, owner: owner, onNonce: (_) {});

      final creates =
          requests.where((r) => r.url.path.endsWith('/set-record')).length;
      expect(creates, 1);
      expect(signs, 3);
      expect(
        requests
            .where((r) => r.url.path.endsWith('/sign'))
            .map((r) => r.body)
            .toSet(),
        hasLength(1),
      );
    });

    test('a failed sign never re-creates the action', () async {
      final c = client((request) async {
        if (request.url.path.endsWith('/sign')) {
          return http.Response(
            'Action action-1 expired and was refunded',
            400,
          );
        }
        return _json({
          'nonce': 'action-1',
          'action': 'set-record',
          'status': 'awaiting-signature',
          'transaction': 'dHg=',
        });
      });

      await expectLater(
        c.run(_set, payer: payer, owner: owner, onNonce: (_) {}),
        throwsA(
          isA<ArNSActionExpiredException>()
              .having((e) => e.refunded, 'refunded', isTrue)
              .having((e) => e.nonce, 'nonce', 'action-1'),
        ),
      );
      expect(
        requests.where((r) => r.url.path.endsWith('/set-record')),
        hasLength(1),
      );
    });

    test('an onNonce that throws stops before any signature prompt', () async {
      final c = client((_) async => _json({
            'nonce': 'action-1',
            'action': 'set-record',
            'status': 'awaiting-signature',
            'transaction': 'dHg=',
          }));

      await expectLater(
        c.run(
          _set,
          payer: payer,
          owner: owner,
          onNonce: (_) => throw Exception('could not persist'),
        ),
        throwsException,
      );
      expect(owner.transactions, isEmpty);
    });
  });

  group('sign errors', () {
    Future<Object> signError(int status, String body) async {
      final c = client((_) async => http.Response(body, status));
      try {
        await c.sign('action-1', 'signed');
      } catch (e) {
        return e;
      }
      fail('expected an error');
    }

    test('409 expired, credits returned', () async {
      final e = await signError(
        409,
        'Action expired; credits have been returned',
      );
      expect(
        e,
        isA<ArNSActionExpiredException>()
            .having((e) => e.refunded, 'refunded', isTrue),
      );
    });

    test('409 expired with a JSON refunded flag', () async {
      final e = await signError(
        409,
        jsonEncode({'error': 'Action expired', 'refunded': false}),
      );
      expect(
        e,
        isA<ArNSActionExpiredException>()
            .having((e) => e.refunded, 'refunded', isFalse)
            .having((e) => e.message, 'message', 'Action expired'),
      );
    });

    test('400 about another expiry is not an expired action', () async {
      final e = await signError(400, 'Lease has expired');
      expect(e, isA<ArNSActionRequestException>());
    });

    test('503 blockhash not found', () async {
      final e = await signError(503, 'Blockhash not found');
      expect(e, isA<ArNSBlockhashNotFoundException>());
    });

    test('402 insufficient credits', () async {
      final e = await signError(402, 'Insufficient balance');
      expect(e, isA<ArNSInsufficientCreditsException>());
    });
  });

  group('status', () {
    test('completed shape', () async {
      final c = client((_) async => _json({
            'nonce': 'action-1',
            'action': 'remove-record',
            'status': 'completed',
            'messageId': 'sig',
          }));

      final result = await c.status('action-1');

      expect(
        requests.single.url.toString(),
        'https://payment.example/v1/arns/actions/action-1',
      );
      expect(
        result,
        isA<ArNSActionCompleted>()
            .having((r) => r.messageId, 'messageId', 'sig'),
      );
    });

    test('awaiting-signature shape', () async {
      final c = client((_) async => _json({
            'nonce': 'action-1',
            'action': 'set-record',
            'status': 'awaiting-signature',
            'transaction': 'dHg=',
            'expiresAt': '2026-10-26T12:00:00Z',
          }));

      expect(
        await c.status('action-1'),
        isA<ArNSActionAwaitingSignature>()
            .having((r) => r.transaction, 'transaction', 'dHg='),
      );
    });

    test('a failedDate is a failure', () async {
      final c = client((_) async => _json({
            'nonce': 'action-1',
            'action': 'set-record',
            'status': 'awaiting-signature',
            'transaction': 'dHg=',
            'failedDate': '2026-10-26T12:00:00Z',
          }));

      expect(await c.status('action-1'), isA<ArNSActionFailed>());
    });

    // After a reload: an action's status is read on the service it was
    // created on, whatever the devnet switch says now.
    test('reads on the payment service the action was made on', () async {
      final c = client((r) async => _json({
            'nonce': 'action-1',
            'action': 'set-record',
            'status': 'completed',
          }));

      await c.status('action-1', paymentUrl: 'https://sandbox.example/');

      expect(requests.map((r) => r.url.toString()), [
        'https://sandbox.example/v1/arns/actions/action-1',
      ]);
      expect(c.paymentUrl, 'https://payment.example');
    });

    test('awaiting-signature with no transaction is not signable', () async {
      final c = client((_) async => _json({
            'nonce': 'action-1',
            'action': 'set-record',
            'status': 'awaiting-signature',
          }));

      expect(
        await c.status('action-1'),
        isA<ArNSActionInProgress>()
            .having((r) => r.status, 'status', 'awaiting-signature'),
      );
    });
  });
}

class _RejectingOwner extends _FakeOwner {
  @override
  Future<Uint8List> signMessage(Uint8List message) async =>
      throw StateError('User rejected the request');
}
