import 'dart:async';

import 'package:ardrive/arns/data/arns_names_repository.dart';
import 'package:ardrive/arns/data/arns_wallet_store.dart';
import 'package:ardrive/arns/domain/arns_action.dart';
import 'package:ardrive/arns/domain/arns_names.dart';
import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_cubit.dart';
import 'package:ardrive/arns/presentation/names/arns_names_cubit.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepository extends Mock implements ArNSNamesRepository {}

class _MockWalletCubit extends MockCubit<ArNSWalletState>
    implements ArNSWalletCubit {}

const _sol = '6eV7bK3bQJdd7Q44doWqAbnBCWNQRhB1HwCDGWf8Qe3V';
const _tx = 'FWswWiH1FMFnuzLFzpqzdgxOBlMS8L7DiP5MxUnWODE';

const _acme = ArNSManagedName(
  name: 'acme',
  processId: 'ant',
  role: ArNSRole.owner,
  type: ArNSNameType.permabuy,
  endTimestamp: null,
  undernameLimit: 10,
  records: [
    ArNSNameRecord(
      name: 'acme',
      undername: 'blog',
      transactionId: _tx,
      ttlSeconds: 300,
    ),
  ],
);

ArNSWalletState _linked() => const ArNSWalletState(
      enabled: true,
      profileAddress: 'profile',
      linked: LinkedArNSWallet(address: _sol),
    );

void main() {
  late _MockRepository repository;
  late _MockWalletCubit wallet;
  late StreamController<ArNSWalletState> walletStates;

  setUp(() {
    repository = _MockRepository();
    wallet = _MockWalletCubit();
    walletStates = StreamController<ArNSWalletState>.broadcast();
  });

  tearDown(() => walletStates.close());

  ArNSNamesCubit build(ArNSWalletState initial) {
    whenListen(wallet, walletStates.stream, initialState: initial);
    return ArNSNamesCubit(repository: repository, walletCubit: wallet);
  }

  test('has nothing while no ArNS wallet is linked', () async {
    final cubit = build(const ArNSWalletState(enabled: true));
    await pumpEventQueue();

    expect(cubit.state.status, ArNSNamesStatus.none);
    verifyZeroInteractions(repository);
  });

  test('has nothing while names are off, even with a wallet remembered',
      () async {
    final cubit = build(const ArNSWalletState(
      profileAddress: 'profile',
      linked: LinkedArNSWallet(address: _sol),
    ));
    await pumpEventQueue();

    expect(cubit.state.status, ArNSNamesStatus.none);
    verifyZeroInteractions(repository);
  });

  test('shows the cache at once, without reading ArNS', () async {
    when(() => repository.cached(_sol)).thenAnswer((_) async => [_acme]);

    final cubit = build(_linked());
    await pumpEventQueue();

    expect(cubit.state.status, ArNSNamesStatus.loaded);
    expect(cubit.state.recordsFor(_tx).single.literalName, 'blog_acme');
    verifyNever(() => repository.refresh(any()));
  });

  test('reads ArNS when nothing is cached yet', () async {
    when(() => repository.cached(_sol)).thenAnswer((_) async => []);
    when(() => repository.refresh(_sol)).thenAnswer((_) async => [_acme]);

    final cubit = build(_linked());
    await pumpEventQueue();

    expect(cubit.state.status, ArNSNamesStatus.loaded);
    expect(cubit.state.names, [_acme]);
  });

  test('a failed refresh keeps the cache and says so', () async {
    when(() => repository.cached(_sol)).thenAnswer((_) async => [_acme]);
    when(() => repository.refresh(_sol)).thenThrow(Exception('RPC'));

    final cubit = build(_linked());
    await pumpEventQueue();
    await cubit.refresh();

    expect(cubit.state.status, ArNSNamesStatus.loaded);
    expect(cubit.state.names, [_acme]);
    expect(cubit.state.refreshFailed, isTrue);
  });

  test('refreshes running at once share one read', () async {
    when(() => repository.cached(_sol)).thenAnswer((_) async => [_acme]);
    final read = Completer<List<ArNSManagedName>>();
    when(() => repository.refresh(_sol)).thenAnswer((_) => read.future);

    final cubit = build(_linked());
    await pumpEventQueue();
    final a = cubit.refresh();
    final b = cubit.refresh();
    read.complete([_acme]);
    await Future.wait([a, b]);

    verify(() => repository.refresh(_sol)).called(1);
  });

  // A refresh begun when the name dialog opened finished after the change
  // the user then made, and put the old records back.
  test('a read that began before a change is made again', () async {
    when(() => repository.cached(_sol)).thenAnswer((_) async => [_acme]);
    final before = Completer<List<ArNSManagedName>>();
    var reads = 0;
    when(() => repository.refresh(_sol)).thenAnswer((_) {
      reads++;
      return reads == 1 ? before.future : Future.value(const []);
    });

    final cubit = build(_linked());
    await pumpEventQueue();
    final running = cubit.refresh();
    cubit.rememberChange(
        const ArNSRemoveRecord(antId: 'ant', undername: 'blog'));
    // The flow's own refresh shares the running one, which reads again.
    final after = cubit.refresh();
    before.complete([_acme]);
    await Future.wait([running, after]);

    expect(reads, 2);
    expect(cubit.state.names, isEmpty);
  });

  // A refresh still running for the old wallet was shared with the new one,
  // which then stayed loading for ever.
  test('a new wallet reads its own names while the old read runs', () async {
    const other = 'BxSiKZJzFYCdKLmTjnrJwMJuZ8u3CPbZRWB7Gw5VtW6c';
    when(() => repository.cached(any())).thenAnswer((_) async => []);
    final oldRead = Completer<List<ArNSManagedName>>();
    final newRead = Completer<List<ArNSManagedName>>();
    when(() => repository.refresh(_sol)).thenAnswer((_) => oldRead.future);
    when(() => repository.refresh(other)).thenAnswer((_) => newRead.future);

    final cubit = build(_linked());
    await pumpEventQueue();
    walletStates.add(const ArNSWalletState(
      enabled: true,
      profileAddress: 'profile',
      linked: LinkedArNSWallet(address: other),
    ));
    await pumpEventQueue();
    verify(() => repository.refresh(other)).called(1);

    // The old read finishing leaves the new one shared.
    oldRead.complete([_acme]);
    await pumpEventQueue();
    final again = cubit.refresh();
    verifyNever(() => repository.refresh(other));

    newRead.complete([_acme]);
    await again;
    expect(cubit.state.address, other);
    expect(cubit.state.status, ArNSNamesStatus.loaded);
    expect(cubit.state.names, [_acme]);
  });

  test('unlinking clears the names', () async {
    when(() => repository.cached(_sol)).thenAnswer((_) async => [_acme]);

    final cubit = build(_linked());
    await pumpEventQueue();
    walletStates.add(const ArNSWalletState(
      enabled: true,
      profileAddress: 'profile',
    ));
    await pumpEventQueue();

    expect(cubit.state.status, ArNSNamesStatus.none);
    expect(cubit.state.names, isEmpty);
  });
}
