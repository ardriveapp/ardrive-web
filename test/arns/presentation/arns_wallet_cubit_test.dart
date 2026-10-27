import 'dart:async';

import 'package:ardrive/arns/data/arns_wallet_store.dart';
import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_cubit.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/key_value_store.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockArioSDK extends Mock implements ArioSDK {}

class _MockAuth extends Mock implements ArDriveAuth {}

class _MockUser extends Mock implements User {}

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

const _profile = 'arweave-profile';
const _sol = '6eV7bK3bQJdd7Q44doWqAbnBCWNQRhB1HwCDGWf8Qe3V';
const _otherSol = 'CBsEKdomKa9nwF4fMiV5iFerfQPT73Et2ZKWpdCLHHsv';
const _phantom = SolanaWalletInfo(name: 'Phantom', icon: 'data:,');

User _user({String? source}) {
  final user = _MockUser();
  when(() => user.walletAddress).thenReturn(_profile);
  when(() => user.sourceWalletAddress).thenReturn(source);
  return user;
}

void main() {
  late _MockArioSDK sdk;
  late _MockAuth auth;
  late ArNSWalletStore store;
  late StreamController<User?> users;
  late StreamController<String?> accounts;
  late StreamController<List<SolanaWalletInfo>> wallets;
  String? connected;

  ArNSWalletCubit build({bool enabled = true}) => ArNSWalletCubit(
        arioSDK: sdk,
        store: store,
        auth: auth,
        isEnabled: () => enabled,
      );

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() {
    sdk = _MockArioSDK();
    auth = _MockAuth();
    final memory = _MemoryStore();
    store = ArNSWalletStore(openStore: () async => memory);
    users = StreamController<User?>.broadcast();
    accounts = StreamController<String?>.broadcast();
    wallets = StreamController<List<SolanaWalletInfo>>.broadcast();
    connected = null;

    when(() => auth.onAuthStateChanged()).thenAnswer((_) => users.stream);
    when(() => auth.currentUser)
        .thenThrow(const AuthenticationUserIsNotLoggedInException());
    when(() => sdk.listSolanaWallets()).thenReturn([_phantom]);
    when(() => sdk.solanaWalletsChanges).thenAnswer((_) => wallets.stream);
    when(() => sdk.solanaAccountChanges).thenAnswer((_) => accounts.stream);
    when(() => sdk.connectedSolanaAddress).thenAnswer((_) => connected);
    when(() => sdk.connectedSolanaWalletName)
        .thenAnswer((_) => connected == null ? null : 'Phantom');
    when(() => sdk.connectSolanaWallet(any(), silent: any(named: 'silent')))
        .thenAnswer((invocation) async {
      final silent = invocation.namedArguments[#silent] as bool;
      if (silent) return null;
      connected = _sol;
      return _sol;
    });
    when(() => sdk.disconnectSolanaWallet()).thenAnswer((_) async {
      connected = null;
    });
  });

  tearDown(() async {
    await users.close();
    await accounts.close();
    await wallets.close();
  });

  test('does nothing while names are off', () async {
    final cubit = build(enabled: false);
    users.add(_user());
    await settle();

    expect(cubit.state.status, ArNSWalletStatus.unavailable);
    verifyNever(() => sdk.listSolanaWallets());
    verifyNever(() => auth.onAuthStateChanged());
    await cubit.close();
  });

  test('a profile with no ArNS wallet is not linked', () async {
    final cubit = build();
    users.add(_user());
    await settle();

    expect(cubit.state.status, ArNSWalletStatus.notLinked);
    expect(cubit.state.noWalletInstalled, isFalse);
    expect(cubit.ownerSigner, isNull);
    await cubit.close();
  });

  test('a Solana sign-in is the ArNS wallet already', () async {
    final cubit = build();
    users.add(_user(source: _sol));
    await settle();

    expect(cubit.state.linked, const LinkedArNSWallet(address: _sol));
    expect(cubit.state.status, ArNSWalletStatus.disconnected);
    expect(await store.linked(_profile), const LinkedArNSWallet(address: _sol));
    await cubit.close();
  });

  test('an Ethereum sign-in links nothing', () async {
    final cubit = build();
    users.add(_user(source: '0xabc'));
    await settle();

    expect(cubit.state.status, ArNSWalletStatus.notLinked);
    await cubit.close();
  });

  test('link connects, remembers the wallet and is ready to sign', () async {
    final cubit = build();
    users.add(_user());
    await settle();

    await cubit.link('Phantom');

    expect(cubit.state.status, ArNSWalletStatus.connected);
    expect(
      await store.linked(_profile),
      const LinkedArNSWallet(address: _sol, walletName: 'Phantom'),
    );
    expect(cubit.ownerSigner?.address, _sol);
    await cubit.close();
  });

  test('a remembered wallet reconnects silently on sign-in', () async {
    await store.link(
      _profile,
      const LinkedArNSWallet(address: _sol, walletName: 'Phantom'),
    );
    when(() => sdk.connectSolanaWallet('Phantom', silent: true))
        .thenAnswer((_) async {
      connected = _sol;
      return _sol;
    });

    final cubit = build();
    users.add(_user());
    await settle();
    await settle();

    expect(cubit.state.status, ArNSWalletStatus.connected);
    verifyNever(() => sdk.connectSolanaWallet('Phantom', silent: false));
    await cubit.close();
  });

  test('switching account in the wallet is the wrong account', () async {
    final cubit = build();
    users.add(_user());
    await settle();
    await cubit.link('Phantom');

    connected = _otherSol;
    accounts.add(_otherSol);
    await settle();

    expect(cubit.state.status, ArNSWalletStatus.wrongAccount);
    expect(cubit.ownerSigner, isNull);
    await cubit.close();
  });

  test('a rejected connect prompt leaves the wallet unlinked', () async {
    when(() => sdk.connectSolanaWallet('Phantom', silent: false))
        .thenThrow(Exception('User rejected the request'));
    final cubit = build();
    users.add(_user());
    await settle();

    await expectLater(cubit.link('Phantom'), throwsException);

    expect(cubit.state.status, ArNSWalletStatus.notLinked);
    expect(cubit.state.connecting, isFalse);
    expect(await store.linked(_profile), isNull);
    await cubit.close();
  });

  test('a Solana sign-in reconnecting remembers the wallet it used', () async {
    final cubit = build();
    users.add(_user(source: _sol));
    await settle();

    await cubit.reconnect(walletName: 'Phantom');

    expect(cubit.state.status, ArNSWalletStatus.connected);
    expect(
      await store.linked(_profile),
      const LinkedArNSWallet(address: _sol, walletName: 'Phantom'),
    );
    await cubit.close();
  });

  test('unlink forgets and disconnects', () async {
    final cubit = build();
    users.add(_user());
    await settle();
    await cubit.link('Phantom');

    await cubit.unlink();

    expect(cubit.state.status, ArNSWalletStatus.notLinked);
    expect(await store.linked(_profile), isNull);
    verify(() => sdk.disconnectSolanaWallet()).called(1);
    await cubit.close();
  });

  test('signing out makes it unavailable', () async {
    final cubit = build();
    users.add(_user(source: _sol));
    await settle();

    users.add(null);
    await settle();

    expect(cubit.state.status, ArNSWalletStatus.unavailable);
    expect(cubit.state.linked, isNull);
    await cubit.close();
  });

  // Left connected, the wallet handed the next profile on the browser the
  // same account when it linked, often without a prompt.
  test('signing out disconnects the wallet', () async {
    final cubit = build();
    users.add(_user());
    await settle();
    await cubit.link('Phantom');

    users.add(null);
    await settle();

    verify(() => sdk.disconnectSolanaWallet()).called(1);
    expect(connected, isNull);
    await cubit.close();
  });

  test('nobody signed in disconnects nothing', () async {
    final cubit = build();
    users.add(null);
    await settle();

    verifyNever(() => sdk.disconnectSolanaWallet());
    await cubit.close();
  });

  test('wallets that register late are listed', () async {
    when(() => sdk.listSolanaWallets()).thenReturn([]);
    final cubit = build();
    expect(cubit.state.noWalletInstalled, isTrue);

    wallets.add([_phantom]);
    await settle();

    expect(cubit.state.installedWallets, [_phantom]);
    await cubit.close();
  });
}
