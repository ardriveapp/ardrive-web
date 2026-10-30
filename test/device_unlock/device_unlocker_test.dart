import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:ardrive/device_unlock/domain/device_key.dart';
import 'package:ardrive/device_unlock/domain/device_secret_source.dart';
import 'package:ardrive/device_unlock/domain/device_unlocker.dart';
import 'package:ardrive/services/arconnect/arconnect_prompt.dart';
import 'package:ardrive/services/arconnect/arconnect_wallet.dart';
import 'package:ardrive/services/ethereum/provider/ethereum_provider_wallet.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart' show decodeBase64ToString;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:webthree/credentials.dart';

import '../test_utils/utils.dart';

/// A wallet that signs differently each time, as a smart-contract wallet or
/// some hardware set-ups do.
Uint8List _randomSignature() =>
    Uint8List.fromList(List.generate(64, (_) => Random.secure().nextInt(256)));

void main() {
  setUpAll(() {
    registerFallbackValue(DataItem());
  });

  /// One account type: how to sign as it, and how to sign as the same
  /// account with a signature that varies.
  final types = <String,
      ({
    DeviceUnlockMethod method,
    DeviceSecretSource Function() steady,
    DeviceSecretSource Function() varying,
    DeviceSecretSource Function() declining,
  })>{};

  late MockArConnectService wander;
  late List<DataItem> wanderSigned;
  final rsa = getTestWallet();

  setUp(() {
    ArConnectPrompt.reset();
    wander = MockArConnectService();
    wanderSigned = [];
    when(() => wander.isExtensionPresent()).thenReturn(true);
  });
  tearDown(ArConnectPrompt.reset);

  Future<ArConnectWallet> wanderWallet(
      Future<Uint8List> Function(DataItem item) sign) async {
    when(() => wander.signDataItem(any())).thenAnswer((call) {
      final item = call.positionalArguments.single as DataItem;
      wanderSigned.add(item);
      return sign(item);
    });
    return ArConnectWallet(wander, publicKey: await rsa.getOwner());
  }

  // Wander: the test wallet signs the item exactly as Wander would.
  types['Wander'] = (
    method: DeviceUnlockMethod.wander,
    steady: () => _LazySource(DeviceUnlockMethod.wander, () async {
          final wallet = await wanderWallet((item) async {
            await item.sign(ArweaveSigner(rsa));
            return base64Url.decode(base64Url.normalize(item.signature));
          });
          return WanderDeviceSecret(wallet);
        }),
    varying: () => _LazySource(DeviceUnlockMethod.wander, () async {
          return WanderDeviceSecret(
              await wanderWallet((_) async => _randomSignature()));
        }),
    declining: () => _LazySource(DeviceUnlockMethod.wander, () async {
          return WanderDeviceSecret(await wanderWallet(
              (_) async => throw 'User cancelled the AuthRequest'));
        }),
  );

  // Phantom and Solflare: the sign-in signature, Ed25519 and so steady.
  final solanaSignature = Uint8List.fromList(List.generate(64, (i) => i * 3));
  types['Phantom'] = (
    method: DeviceUnlockMethod.solana,
    steady: () => SolanaDeviceSecret(() async => solanaSignature),
    varying: () => SolanaDeviceSecret(() async => _randomSignature()),
    declining: () =>
        SolanaDeviceSecret(() async => throw 'User rejected the request.'),
  );

  // MetaMask: a real secp256k1 personal_sign, deterministic by RFC 6979.
  final eth = EthereumProviderWallet(
      EthPrivateKey(Uint8List.fromList(List.generate(32, (i) => i + 1))));
  types['MetaMask'] = (
    method: DeviceUnlockMethod.ethereum,
    steady: () => EthereumDeviceSecret(eth),
    varying: () => EthereumDeviceSecret(_VaryingEthereumWallet()),
    declining: () => EthereumDeviceSecret(_DecliningEthereumWallet()),
  );

  for (final MapEntry(key: name, value: type) in types.entries) {
    group('$name device unlock', () {
      late DeviceUnlocker unlocker;
      late DeviceRecord record;

      setUp(() async {
        unlocker = DeviceUnlocker();
        final salt = newDeviceSalt();
        Uint8List? check;
        // The first session makes the key check, as a sign-in would.
        final first = await DeviceUnlocker().unlockToRemember(
          record: DeviceRecord(method: type.method, deviceSalt: salt),
          source: type.steady(),
          saveKeyCheck: (c) async => check = c,
        );
        expect(first.status, DeviceUnlockStatus.unlocked);
        record = DeviceRecord(
            method: type.method, deviceSalt: salt, keyCheck: check);
      });

      test('the same wallet opens what it remembered, with one prompt',
          () async {
        var asked = 0;
        final source = _Counting(type.steady(), () => asked++);

        final outcome = await unlocker.unlockToRead(
          record: record,
          source: source,
          hasRemembered: () async => true,
        );
        final again = await unlocker.unlockToRead(
          record: record,
          source: source,
          hasRemembered: () async => true,
        );

        expect(outcome.status, DeviceUnlockStatus.unlocked);
        expect(again.key, same(outcome.key));
        expect(asked, 1);
      });

      test(
          'a cancelled prompt leaves the drives locked, and is not asked '
          'again this session', () async {
        var asked = 0;
        final source = _Counting(type.declining(), () => asked++);

        final outcome = await unlocker.unlockToRead(
          record: record,
          source: source,
          hasRemembered: () async => true,
        );
        final remembering =
            await unlocker.unlockToRemember(record: record, source: source);

        expect(outcome.status, DeviceUnlockStatus.declined);
        expect(outcome.key, isNull);
        expect(remembering.key, isNull);
        expect(asked, 1);
      });

      test('a signature that varies fails cleanly to locked drives', () async {
        final outcome = await unlocker.unlockToRead(
          record: record,
          source: type.varying(),
          hasRemembered: () async => true,
        );

        expect(outcome.status, DeviceUnlockStatus.mismatch);
        expect(outcome.key, isNull);
        expect(unlocker.key, isNull);
      });

      test('nothing remembered: nobody is asked', () async {
        var asked = 0;
        final outcome = await unlocker.unlockToRead(
          record: record,
          source: _Counting(type.steady(), () => asked++),
          hasRemembered: () async => false,
        );

        expect(outcome.status, DeviceUnlockStatus.nothingRemembered);
        expect(asked, 0);
        expect(unlocker.asked, isFalse);
      });

      test('two callers at once share one prompt', () async {
        var asked = 0;
        final source = _Counting(type.steady(), () => asked++);

        final both = await Future.wait([
          unlocker.unlockToRead(
              record: record, source: source, hasRemembered: () async => true),
          unlocker.unlockToRemember(record: record, source: source),
        ]);

        expect(both.map((o) => o.status),
            everyElement(DeviceUnlockStatus.unlocked));
        expect(asked, 1);
      });

      test('signing out lets the next session ask again', () async {
        var asked = 0;
        final source = _Counting(type.steady(), () => asked++);
        await unlocker.unlockToRead(
            record: record, source: source, hasRemembered: () async => true);

        unlocker.clear();
        expect(unlocker.key, isNull);
        await unlocker.unlockToRead(
            record: record, source: source, hasRemembered: () async => true);

        expect(asked, 2);
      });
    });
  }

  group('Wander', () {
    test('signs one fixed item: the device salt, tagged Unlock-Device-V1',
        () async {
      final wallet = await wanderWallet((item) async {
        await item.sign(ArweaveSigner(rsa));
        return base64Url.decode(base64Url.normalize(item.signature));
      });
      final salt = newDeviceSalt();

      final a = await WanderDeviceSecret(wallet).secret(salt);
      final b = await WanderDeviceSecret(wallet).secret(salt);

      expect(a, b, reason: 'salt length 0: the same item, the same signature');
      final item = wanderSigned.first;
      expect(item.data, salt);
      expect(item.target, isEmpty);
      expect(item.nonce, isEmpty);
      expect(
        item.tags.map((t) =>
            '${decodeBase64ToString(t.name)}=${decodeBase64ToString(t.value)}'),
        ['App-Name=ArDrive', 'Action=Unlock-Device-V1'],
      );
    });

    test('a Wander that never answers ends declined, through its deadline',
        () async {
      ArConnectPrompt.signTimeout = const Duration(milliseconds: 50);
      final wallet = await wanderWallet((_) => Completer<Uint8List>().future);

      final outcome = await DeviceUnlocker().unlockToRemember(
        record: DeviceRecord(
            method: DeviceUnlockMethod.wander, deviceSalt: newDeviceSalt()),
        source: WanderDeviceSecret(wallet),
        saveKeyCheck: (_) async {},
      );

      expect(outcome.status, DeviceUnlockStatus.declined);
    });

    test('the waiting line shows only while Wander is asked', () async {
      final answer = Completer<Uint8List>();
      final wallet = await wanderWallet((_) => answer.future);
      final unlocker = DeviceUnlocker();

      final pending = unlocker.unlockToRemember(
        record: DeviceRecord(
            method: DeviceUnlockMethod.wander, deviceSalt: newDeviceSalt()),
        source: WanderDeviceSecret(wallet),
        saveKeyCheck: (_) async {},
      );
      await pumpEventQueue();
      expect(unlocker.isWaitingOnWallet, isTrue);

      answer.complete(_randomSignature());
      await pending;
      expect(unlocker.isWaitingOnWallet, isFalse);
    });
  });

  test('a password never shows the waiting line', () async {
    final unlocker = DeviceUnlocker();
    final seen = <bool>[];
    unlocker.waitingOnWallet.listen(seen.add);

    await unlocker.unlockToRemember(
      record: DeviceRecord(
          method: DeviceUnlockMethod.password, deviceSalt: newDeviceSalt()),
      source: PasswordDeviceSecret(password: 'pw', keySalt: [1, 2, 3, 4]),
      saveKeyCheck: (_) async {},
    );
    await pumpEventQueue();

    expect(seen, isNot(contains(true)));
  });

  test('a source for another method opens nothing', () async {
    final outcome = await DeviceUnlocker().unlockToRemember(
      record: DeviceRecord(
          method: DeviceUnlockMethod.wander, deviceSalt: newDeviceSalt()),
      source: SolanaDeviceSecret(() async => _randomSignature()),
      saveKeyCheck: (_) async {},
    );
    expect(outcome.key, isNull);
  });

  test('an unlock that throws lets the next caller ask again', () async {
    final unlocker = DeviceUnlocker();
    final record = DeviceRecord(
        method: DeviceUnlockMethod.solana, deviceSalt: newDeviceSalt());
    final source = SolanaDeviceSecret(() async => _randomSignature());
    var saves = 0;

    await expectLater(
      unlocker.unlockToRemember(
        record: record,
        source: source,
        saveKeyCheck: (_) async {
          saves++;
          throw StateError('the disk is full');
        },
      ),
      throwsA(isA<StateError>()),
    );
    final again = await unlocker.unlockToRemember(
      record: record,
      source: source,
      saveKeyCheck: (_) async => saves++,
    );

    expect(again.status, DeviceUnlockStatus.unlocked);
    expect(saves, 2);
  });
}

class _Counting implements DeviceSecretSource {
  _Counting(this._inner, this._onAsk);

  final DeviceSecretSource _inner;
  final void Function() _onAsk;

  @override
  DeviceUnlockMethod get method => _inner.method;

  @override
  Future<Uint8List> secret(Uint8List deviceSalt) {
    _onAsk();
    return _inner.secret(deviceSalt);
  }
}

/// Builds its source on first use, so the Wander mock is set up inside the
/// test that uses it.
class _LazySource implements DeviceSecretSource {
  _LazySource(this.method, this._build);

  @override
  final DeviceUnlockMethod method;
  final Future<DeviceSecretSource> Function() _build;

  @override
  Future<Uint8List> secret(Uint8List deviceSalt) async =>
      (await _build()).secret(deviceSalt);
}

class _VaryingEthereumWallet extends EthereumProviderWallet {
  _VaryingEthereumWallet()
      : super(
            EthPrivateKey(Uint8List.fromList(List.generate(32, (i) => i + 1))));

  @override
  Future<Uint8List> sign(Uint8List message, [String? context]) async =>
      _randomSignature();
}

class _DecliningEthereumWallet extends EthereumProviderWallet {
  _DecliningEthereumWallet()
      : super(
            EthPrivateKey(Uint8List.fromList(List.generate(32, (i) => i + 1))));

  @override
  Future<Uint8List> sign(Uint8List message, [String? context]) async =>
      throw 'User rejected the request.';
}
