import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/device_unlock/domain/device_key.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final salt = Uint8List.fromList(List.generate(deviceSaltLength, (i) => i));
  final secret = utf8.encode('a wallet signature');

  Future<SecretKey> key(
    DeviceUnlockMethod method, {
    List<int>? withSecret,
    List<int>? withSalt,
  }) =>
      deriveDeviceKey(
        secret: withSecret ?? secret,
        deviceSalt: withSalt ?? salt,
        method: method,
      );

  test('the device key depends on the secret, the salt and the method',
      () async {
    final base = await (await key(DeviceUnlockMethod.wander)).extractBytes();

    expect(await (await key(DeviceUnlockMethod.wander)).extractBytes(), base);
    expect(
      await (await key(DeviceUnlockMethod.solana)).extractBytes(),
      isNot(base),
    );
    expect(
      await (await key(DeviceUnlockMethod.wander, withSecret: [1, 2, 3]))
          .extractBytes(),
      isNot(base),
    );
    expect(
      await (await key(DeviceUnlockMethod.wander, withSalt: newDeviceSalt()))
          .extractBytes(),
      isNot(base),
    );
  });

  test('every seal has its own nonce', () async {
    final deviceKey = await key(DeviceUnlockMethod.password);
    final nonces = <String>{};

    for (var i = 0; i < 200; i++) {
      final sealed = await seal(deviceKey, utf8.encode('the same plaintext'));
      nonces.add(base64.encode(sealed.sublist(0, 12)));
    }

    expect(nonces, hasLength(200));
  });

  test('a seal opens with its key and with no other', () async {
    final deviceKey = await key(DeviceUnlockMethod.password);
    final other = await key(DeviceUnlockMethod.password, withSecret: [9]);
    final sealed = await seal(deviceKey, utf8.encode('wallet'));

    expect(utf8.decode(await openSealed(deviceKey, sealed)), 'wallet');
    expect(
      () => openSealed(other, sealed),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
    expect(
      () => openSealed(deviceKey, sealed.sublist(0, 20)),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('the key check tells the right key from any other', () async {
    final deviceKey = await key(DeviceUnlockMethod.ethereum);
    final check = await makeKeyCheck(deviceKey);

    expect(await keyCheckMatches(deviceKey, check), isTrue);
    expect(
      await keyCheckMatches(
          await key(DeviceUnlockMethod.ethereum, withSecret: [7]), check),
      isFalse,
    );
  });

  test('the stored method values never change', () {
    expect(DeviceUnlockMethod.values.map((m) => m.value),
        ['password', 'wander', 'solana', 'ethereum']);
    expect(DeviceUnlockMethod.fromValue('wander'), DeviceUnlockMethod.wander);
    expect(DeviceUnlockMethod.fromValue('passkey'), isNull);
  });

  test('the MetaMask message is fixed and readable', () {
    expect(
      ethereumDeviceUnlockMessage('0xABCdef'),
      'ArDrive device unlock\n'
      'Open what ArDrive remembers on this device.\n'
      'Account: 0xabcdef\n'
      'Version: 1',
    );
  });
}
