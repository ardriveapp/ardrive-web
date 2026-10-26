import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/arns/data/arns_pending_action_store.dart';
import 'package:ardrive/arns/data/arns_wallet_store.dart';
import 'package:ardrive/arns/data/turbo_arns_action_client.dart';
import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_cubit.dart';
import 'package:ardrive/arns/presentation/names/arns_names_cubit.dart';
import 'package:ardrive/arns/presentation/resume/arns_resume_cubit.dart';
import 'package:ardrive/utils/key_value_store.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';

class _MockWalletCubit extends MockCubit<ArNSWalletState>
    implements ArNSWalletCubit {}

class _MockNamesCubit extends MockCubit<ArNSNamesState>
    implements ArNSNamesCubit {}

class _MemoryStore implements KeyValueStore {
  final values = <String, String>{};

  @override
  Future<bool> putString(String key, String value) async {
    values[key] = value;
    return true;
  }

  @override
  String? getString(String key) => values[key];

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }

  @override
  Set<String> getKeys() => values.keys.toSet();

  @override
  Future<bool> putBool(String key, bool value) async => true;

  @override
  bool? getBool(String key) => null;
}

class _Owner implements ArNSOwnerSigner {
  final signed = <String>[];

  @override
  String get address => _sol;

  @override
  Future<Uint8List> signMessage(Uint8List message) async =>
      Uint8List.fromList(List.filled(64, 7));

  @override
  Future<String> signTransaction(String transactionBase64) async {
    signed.add(transactionBase64);
    return 'signed-$transactionBase64';
  }
}

const _sol = '6eV7bK3bQJdd7Q44doWqAbnBCWNQRhB1HwCDGWf8Qe3V';
const _profile = 'profile';
const _sandbox = 'https://sandbox.example';
final _now = DateTime.utc(2026, 10, 26, 12);

ArNSPendingAction _action(String nonce, {Duration age = Duration.zero}) =>
    ArNSPendingAction(
      nonce: nonce,
      paymentUrl: _sandbox,
      name: 'blog_acme',
      description: 'set-record blog_acme -> tx',
      createdAt: _now.subtract(age),
    );

ArNSWalletState _signedIn({bool enabled = true}) => ArNSWalletState(
      enabled: enabled,
      profileAddress: _profile,
      linked: const LinkedArNSWallet(address: _sol),
      connectedAddress: _sol,
    );

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

void main() {
  late _MockWalletCubit wallet;
  late _MockNamesCubit names;
  late ArNSPendingActionStore store;
  late List<http.Request> requests;
  late Map<String, http.Response Function(http.Request)> routes;
  late _Owner owner;

  ArNSResumeCubit build({ArNSWalletState? state}) {
    whenListen(
      wallet,
      const Stream<ArNSWalletState>.empty(),
      initialState: state ?? _signedIn(),
    );
    return ArNSResumeCubit(
      store: store,
      client: TurboArNSActionClient(
        paymentUrl: () => 'https://payment.example',
        client: MockClient((request) async {
          requests.add(request);
          final route = routes['${request.method} ${request.url}'];
          if (route == null) return http.Response('not found', 404);
          return route(request);
        }),
        delay: (_) async {},
      ),
      walletCubit: wallet,
      namesCubit: names,
      clock: () => _now,
    );
  }

  /// Lets the check started by the constructor finish.
  Future<void> settle() => pumpEventQueue();

  void status(String nonce, Map<String, Object> body, [int code = 200]) {
    routes['GET $_sandbox/v1/arns/actions/$nonce'] = (_) => _json(body, code);
  }

  setUp(() async {
    wallet = _MockWalletCubit();
    names = _MockNamesCubit();
    when(() => names.refresh()).thenAnswer((_) async {});
    owner = _Owner();
    when(() => wallet.ownerSigner).thenReturn(owner);
    final memory = _MemoryStore();
    store = ArNSPendingActionStore(openStore: () async => memory);
    requests = [];
    routes = {};
  });

  test('a change that went through says Name saved and reads the names',
      () async {
    await store.add(_profile, _action('a1'));
    status('a1', {'nonce': 'a1', 'status': 'completed', 'messageId': 'm'});

    final cubit = build();
    await settle();

    expect(
      cubit.state.notice,
      const ArNSResumeNotice(
        outcome: ArNSResumeOutcome.saved,
        name: 'blog_acme',
        nonce: 'a1',
      ),
    );
    verify(() => names.refresh()).called(1);
    expect(await store.pending(_profile), isEmpty);
    expect(requests.map((r) => r.method), ['GET'],
        reason: 'a status read only: never a second create');
  });

  test('a failed or expired change says the credits come back', () async {
    await store.add(_profile, _action('a1'));
    await store.add(_profile, _action('a2'));
    status('a1', {
      'nonce': 'a1',
      'status': 'failed',
      'failedDate': '2026-10-26T11:00:00Z',
    });
    status('a2', {'nonce': 'a2', 'status': 'expired'});

    final cubit = build();
    final seen = <ArNSResumeNotice?>[];
    final sub = cubit.stream.listen((s) => seen.add(s.notice));
    await settle();
    await sub.cancel();

    expect(seen.map((n) => (n?.outcome, n?.nonce)), [
      (ArNSResumeOutcome.refunding, 'a1'),
      (ArNSResumeOutcome.refunding, 'a2'),
    ]);
    expect(await store.pending(_profile), isEmpty);
    verifyNever(() => names.refresh());
  });

  group('awaiting the ArNS wallet', () {
    test('offers to finish, and finishing signs and submits only', () async {
      await store.add(_profile, _action('a1'));
      status('a1', {
        'nonce': 'a1',
        'status': 'awaiting-signature',
        'transaction': 'dHg=',
        'expiresAt': '2026-10-26T12:10:00Z',
      });
      routes['POST $_sandbox/v1/arns/actions/a1/sign'] =
          (_) => _json({'nonce': 'a1', 'status': 'completed'});

      final cubit = build();
      await settle();

      expect(cubit.state.notice?.outcome, ArNSResumeOutcome.canFinish);
      expect(await store.pending(_profile), hasLength(1),
          reason: 'kept until it ends');

      await cubit.finish('a1');

      expect(owner.signed, ['dHg=']);
      expect(
        requests.map((r) => '${r.method} ${r.url.path}'),
        ['GET /v1/arns/actions/a1', 'POST /v1/arns/actions/a1/sign'],
      );
      expect(jsonDecode(requests.last.body), {'transaction': 'signed-dHg='});
      expect(cubit.state.notice?.outcome, ArNSResumeOutcome.saved);
      expect(await store.pending(_profile), isEmpty);
      verify(() => names.refresh()).called(1);
    });

    test('finishing too late says the credits come back', () async {
      await store.add(_profile, _action('a1'));
      status('a1', {
        'nonce': 'a1',
        'status': 'awaiting-signature',
        'transaction': 'dHg=',
      });
      routes['POST $_sandbox/v1/arns/actions/a1/sign'] =
          (_) => _json({'error': 'Action expired', 'refunded': true}, 409);

      final cubit = build();
      await settle();
      await cubit.finish('a1');

      expect(cubit.state.notice?.outcome, ArNSResumeOutcome.refunding);
      expect(await store.pending(_profile), isEmpty);
    });

    test('past its expiry, nothing is offered', () async {
      await store.add(_profile, _action('a1'));
      status('a1', {
        'nonce': 'a1',
        'status': 'awaiting-signature',
        'transaction': 'dHg=',
        'expiresAt': '2026-10-26T11:59:00Z',
      });

      final cubit = build();
      await settle();

      expect(cubit.state.notice?.outcome, ArNSResumeOutcome.refunding);
      expect(await store.pending(_profile), isEmpty);
    });

    test('with no transaction to sign, it will expire and be refunded',
        () async {
      await store.add(_profile, _action('a1'));
      status('a1', {'nonce': 'a1', 'status': 'awaiting-signature'});

      final cubit = build();
      await settle();

      expect(cubit.state.notice?.outcome, ArNSResumeOutcome.refunding);
      expect(await store.pending(_profile), isEmpty);
    });
  });

  test('a status that cannot be read now is asked again next time', () async {
    await store.add(_profile, _action('a1'));
    routes['GET $_sandbox/v1/arns/actions/a1'] =
        (_) => throw http.ClientException('offline');

    final cubit = build();
    await settle();

    expect(cubit.state.notice, isNull);
    expect(await store.pending(_profile), hasLength(1));
  });

  test('an unresolved action a day old is dropped quietly', () async {
    await store.add(_profile, _action('a1', age: const Duration(days: 2)));
    status('a1', {'nonce': 'a1', 'status': 'pending'});

    final cubit = build();
    await settle();

    expect(cubit.state.notice, isNull);
    expect(await store.pending(_profile), isEmpty);
  });

  test('nothing is read while names are off', () async {
    await store.add(_profile, _action('a1'));
    status('a1', {'nonce': 'a1', 'status': 'completed'});

    final cubit = build(state: _signedIn(enabled: false));
    await settle();

    expect(requests, isEmpty);
    expect(cubit.state.notice, isNull);
  });

  test('nothing is read before anyone signs in', () async {
    await store.add(_profile, _action('a1'));

    build(state: const ArNSWalletState(enabled: true));
    await settle();

    expect(requests, isEmpty);
  });
}
