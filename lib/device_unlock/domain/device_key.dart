import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// How this device's key is made. Stored on the profile as `unlockMethod`,
/// so the value strings must never change.
///
/// The device key is the one secret per session that opens what this device
/// remembers: the stored wallet (for the account types that store one) and
/// the remembered drive keys. See the 3.0 password design, "Device unlock".
enum DeviceUnlockMethod {
  /// The device password. Generated, recovery phrase and keyfile accounts,
  /// and in 3.0's first step every account, since every account still signs
  /// in with a password.
  password('password'),

  /// One Wander `signDataItem` of a fixed item holding the device salt.
  wander('wander'),

  /// The Phantom or Solflare sign-in signature.
  solana('solana'),

  /// A MetaMask `personal_sign` of [ethereumDeviceUnlockMessage].
  ethereum('ethereum');

  const DeviceUnlockMethod(this.value);

  final String value;

  /// The method stored as [value], or null for a value this build does not
  /// know, which the caller treats as a profile it can't open.
  static DeviceUnlockMethod? fromValue(String? value) {
    for (final method in values) {
      if (method.value == value) return method;
    }
    return null;
  }

  /// Whether getting this method's secret shows the person a wallet prompt.
  bool get prompts => this != password;
}

/// Bytes of random salt kept on the device, one per profile.
///
/// A wallet signature is the same wherever it is asked for, so another site
/// that gets the person to sign the same thing gets the same signature. The
/// salt, which never leaves this device, is what makes the key this device's
/// alone: it goes into the key derivation, and for Wander into the signed
/// item itself.
const deviceSaltLength = 32;

const _nonceLength = 12;
const _macLength = 16;

final _aesGcm = AesGcm.with256bits();
final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
final _random = Random.secure();

Uint8List randomBytes(int length) =>
    Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));

Uint8List newDeviceSalt() => randomBytes(deviceSaltLength);

/// The device key: HKDF-SHA256 of [secret], salted with the device salt, with
/// the method in `info` so two methods never share a key.
Future<SecretKey> deriveDeviceKey({
  required List<int> secret,
  required List<int> deviceSalt,
  required DeviceUnlockMethod method,
}) =>
    _hkdf.deriveKey(
      secretKey: SecretKey(secret),
      nonce: deviceSalt,
      info: utf8.encode('ArDrive-Device-Key-V1/${method.value}'),
    );

/// What a key derived from the device key is for. Each purpose has its own
/// key ([deviceSubkey]), so no two kinds of value are ever sealed under the
/// same key. The value strings are part of the format and never change.
enum DeviceKeyPurpose {
  wallet('wallet'),
  publicKey('public-key'),
  keyCheck('key-check'),
  driveKey('drive-key');

  const DeviceKeyPurpose(this.value);

  final String value;
}

/// The key for [purpose]: HKDF-SHA256 of the device key, with the purpose in
/// `info`.
Future<SecretKey> deviceSubkey(
  SecretKey deviceKey,
  DeviceKeyPurpose purpose,
) async =>
    _hkdf.deriveKey(
      secretKey: SecretKey(await deviceKey.extractBytes()),
      // No salt: RFC 5869's default, a hash length of zeros. The device key
      // is already uniformly random.
      nonce: List<int>.filled(32, 0),
      info: utf8.encode('ArDrive-Device-Key-V1/${purpose.value}'),
    );

/// The additional authenticated data of a drive key wrapped on its drive
/// row: the wrap opens only on the row of the drive it was made for.
List<int> driveKeyAad(String driveId) => utf8.encode('drive-key/$driveId');

/// Encrypts [plaintext] under [key] with AES-256-GCM and a fresh random
/// nonce, returned as `nonce || ciphertext || mac`.
///
/// A fresh nonce every time is the point: the profile format before this
/// encrypted the wallet and the public key under one key with one nonce.
Future<Uint8List> seal(
  SecretKey key,
  List<int> plaintext, {
  List<int> aad = const <int>[],
}) async {
  final box = await _aesGcm.encrypt(
    plaintext,
    secretKey: key,
    nonce: _aesGcm.newNonce(),
    aad: aad,
  );
  return box.concatenation();
}

/// Decrypts what [seal] made. Throws [SecretBoxAuthenticationError] when
/// [key] is not the one it was sealed with.
Future<Uint8List> openSealed(
  SecretKey key,
  List<int> sealed, {
  List<int> aad = const <int>[],
}) async {
  if (sealed.length < _nonceLength + _macLength) {
    throw SecretBoxAuthenticationError();
  }
  final box = SecretBox.fromConcatenation(
    sealed,
    nonceLength: _nonceLength,
    macLength: _macLength,
  );
  return Uint8List.fromList(
      await _aesGcm.decrypt(box, secretKey: key, aad: aad));
}

const _keyCheckPlaintext = 'ArDrive device key check v1';

/// A known plaintext sealed under the device key's key-check subkey, kept on
/// the profile.
///
/// It is how a wallet whose signature changes from one request to the next
/// (a smart-contract wallet, some hardware set-ups) is caught: its key opens
/// nothing, and the remembered values are treated as absent, so the person
/// sees locked drives rather than wrong data.
Future<Uint8List> makeKeyCheck(SecretKey deviceKey) async => seal(
    await deviceSubkey(deviceKey, DeviceKeyPurpose.keyCheck),
    utf8.encode(_keyCheckPlaintext));

/// Whether [deviceKey] opens [keyCheck].
Future<bool> keyCheckMatches(SecretKey deviceKey, List<int> keyCheck) async {
  try {
    final plain = await openSealed(
        await deviceSubkey(deviceKey, DeviceKeyPurpose.keyCheck), keyCheck);
    return utf8.decode(plain, allowMalformed: true) == _keyCheckPlaintext;
  } on SecretBoxAuthenticationError {
    return false;
  }
}

/// The message MetaMask signs for the device key. Readable, versioned, and
/// fixed: changing it changes every MetaMask device key, so it never changes;
/// a new version gets a new method.
String ethereumDeviceUnlockMessage(String address) => 'ArDrive device unlock\n'
    'Open what ArDrive remembers on this device.\n'
    'This is free and sends no transaction. Only sign it in ArDrive.\n'
    'Account: ${address.toLowerCase()}\n'
    'Version: 1';

/// The tags of the item Wander signs for the device key. Its data is the
/// device salt.
const wanderDeviceUnlockTags = {
  'App-Name': 'ArDrive',
  'Action': 'Unlock-Device-V1',
};

/// Wraps [driveKey] for the row of [driveId]: AES-256-GCM under [wrapKey]
/// (the session's drive-key subkey), a fresh nonce, and [driveKeyAad]. The
/// row keeps the ciphertext and MAC in `encryptedKey` and the nonce in
/// `keyEncryptionIv`.
Future<SecretBox> wrapDriveKey(
  List<int> driveKey,
  SecretKey wrapKey,
  String driveId,
) =>
    _aesGcm.encrypt(
      driveKey,
      secretKey: wrapKey,
      nonce: _aesGcm.newNonce(),
      aad: driveKeyAad(driveId),
    );

/// Opens what [wrapDriveKey] made. Throws [SecretBoxAuthenticationError] for
/// a wrong key or a wrap made for another drive.
///
/// A row written before format 2 has no AAD, and is opened without it. Only
/// a format 1 profile's key opens such a row: every format 2 key is new, and
/// everything format 2 writes has the AAD.
Future<List<int>> unwrapDriveKey({
  required List<int> encryptedKey,
  required List<int> iv,
  required SecretKey wrapKey,
  required String driveId,
}) async {
  if (encryptedKey.length < _macLength) throw SecretBoxAuthenticationError();
  final box = SecretBox(
    encryptedKey.sublist(0, encryptedKey.length - _macLength),
    nonce: iv,
    mac: Mac(encryptedKey.sublist(encryptedKey.length - _macLength)),
  );
  try {
    return await _aesGcm.decrypt(box,
        secretKey: wrapKey, aad: driveKeyAad(driveId));
  } on SecretBoxAuthenticationError {
    return _aesGcm.decrypt(box, secretKey: wrapKey);
  }
}
