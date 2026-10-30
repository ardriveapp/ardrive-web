import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:ardrive/utils/key_value_store.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/drive_signature.dart';
import 'package:ardrive/entities/drive_signature_type.dart';
import 'package:ardrive/services/arconnect/arconnect.dart';
import 'package:ardrive/services/arconnect/arconnect_wallet.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:flutter_test/flutter_test.dart';

/// A drive transaction as the gateway lists it, built in memory.
class FakeDriveTx with TransactionCommonMixin {
  FakeDriveTx({
    required String id,
    required String ownerAddress,
    required Map<String, String> tags,
  }) {
    this.id = id;
    owner = TransactionCommonMixin$Owner()..address = ownerAddress;
    this.tags = [
      for (final entry in tags.entries)
        TransactionCommonMixin$Tag()
          ..name = entry.key
          ..value = entry.value,
    ];
  }
}

/// A private drive as it is on chain: its newest metadata transaction and
/// that metadata, encrypted with the key [password] derives for [wallet].
class PrivateDriveFixture {
  PrivateDriveFixture({
    required this.driveId,
    required this.tx,
    required this.data,
    required this.key,
    this.record,
  });

  final String driveId;
  final TransactionCommonMixin tx;
  final Uint8List data;

  /// The key that opens it.
  final DriveKey key;

  /// For a v1 drive made with a stored signature: the drive-signature record.
  final DriveSignatureEntity? record;
}

int _txCounter = 0;

/// Makes a private drive whose key is derived from [passwordInfo] - the bytes
/// the HKDF takes - so a test can make the drives core-js makes for a
/// non-ASCII password, as well as web's.
///
/// [withRecord] makes a v1 drive whose v1 signature is stored on chain
/// encrypted under its v2 key, as the migration writes.
Future<PrivateDriveFixture> makePrivateDrive({
  required Wallet wallet,
  required String driveId,
  required List<int> passwordInfo,
  DriveSignatureType signatureType = DriveSignatureType.v2,
  bool withRecord = false,
  String name = 'Drive',
  String rootFolderId = '11111111-1111-4111-8111-111111111111',
  int unixTime = 1790000000,
}) async {
  final crypto = ArDriveCrypto();

  DriveKey key;
  DriveSignatureEntity? record;

  if (withRecord) {
    final v1Signature = await crypto.walletSignatureForDrive(
        wallet, driveId, DriveSignatureType.v1);
    final v2Signature = await crypto.walletSignatureForDrive(
        wallet, driveId, DriveSignatureType.v2);
    final v2Key = await crypto.driveKeyFromSignature(v2Signature, passwordInfo,
        generated: false);
    final box = await crypto.encrypt(v1Signature, v2Key.key);

    record = DriveSignatureEntity(
      driveId: driveId,
      signatureFormat: '1',
      cipher: 'AES256-GCM',
      cipherIv: utils.encodeBytesToBase64(box.nonce),
      data: Uint8List.fromList(box.concatenation(nonce: false)),
    );
    key = await crypto.driveKeyFromSignature(v1Signature, passwordInfo,
        generated: false);
  } else {
    final signature =
        await crypto.walletSignatureForDrive(wallet, driveId, signatureType);
    key = await crypto.driveKeyFromSignature(signature, passwordInfo,
        generated: true);
  }

  final box = await crypto.encrypt(
    Uint8List.fromList(
        utf8.encode(json.encode({'name': name, 'rootFolderId': rootFolderId}))),
    key.key,
  );

  final tx = FakeDriveTx(
    id: 'drive-tx-${_txCounter++}',
    ownerAddress: await wallet.getAddress(),
    tags: {
      EntityTag.arFs: '0.15',
      EntityTag.entityType: EntityTypeTag.drive,
      EntityTag.driveId: driveId,
      EntityTag.drivePrivacy: DrivePrivacyTag.private,
      EntityTag.driveAuthMode: DriveAuthModeTag.password,
      if (signatureType != DriveSignatureType.v1 || !withRecord)
        EntityTag.signatureType: signatureType.value,
      EntityTag.cipher: 'AES256-GCM',
      EntityTag.cipherIv: utils.encodeBytesToBase64(box.nonce),
      EntityTag.unixTime: '$unixTime',
    },
  );

  return PrivateDriveFixture(
    driveId: driveId,
    tx: tx,
    data: Uint8List.fromList(box.concatenation(nonce: false)),
    key: key,
    record: record,
  );
}

/// [makePrivateDrive] with a password, encoded as web encodes it.
Future<PrivateDriveFixture> makeWebPrivateDrive({
  required Wallet wallet,
  required String driveId,
  required String password,
  DriveSignatureType signatureType = DriveSignatureType.v2,
  bool withRecord = false,
  String name = 'Drive',
  int unixTime = 1790000000,
}) =>
    makePrivateDrive(
      wallet: wallet,
      driveId: driveId,
      passwordInfo: utf8.encode(password),
      signatureType: signatureType,
      withRecord: withRecord,
      name: name,
      unixTime: unixTime,
    );

/// Counts a wallet's signatures, and can make it refuse them the way a
/// cancelled Wander prompt does. Use [wallet].
class SignatureCounter {
  SignatureCounter(Map<String, dynamic> jwk) {
    wallet = Wallet.fromJwk(jwk, onSign: (_, __) {
      signatures++;
      if (refuse) {
        throw Exception('User cancelled the signature');
      }
    });
  }

  late final Wallet wallet;

  int signatures = 0;
  bool refuse = false;
}

/// Wander, as far as signing goes: every signature is a prompt, counted, and
/// it can be made to cancel them, fail them, or answer v2 differently each
/// time. Signs with [inner], so its keys are the JWK wallet's. Use [wallet].
class FakeWander extends Fake implements ArConnectService {
  FakeWander(this.inner);

  final Wallet inner;

  late final ArConnectWallet wallet = ArConnectWallet(this);

  int prompts = 0;

  /// Throws what Wander throws when its prompt is cancelled.
  bool cancel = false;

  /// Throws as a wallet that can't sign at all.
  bool fail = false;

  /// Answers every v2 (data item) signature with fresh random bytes.
  bool varyV2 = false;

  void _prompt() {
    prompts++;
    if (cancel) throw Exception('User cancelled the auth');
    if (fail) throw Exception('Wallet is locked');
  }

  @override
  Future<String> getWalletAddress() => inner.getAddress();

  @override
  Future<String> getPublicKey() => inner.getOwner();

  @override
  Future<Uint8List> getSignature(Uint8List message) async {
    _prompt();
    return inner.sign(message);
  }

  @override
  Future<Uint8List> signDataItem(DataItem dataItem) async {
    _prompt();
    if (varyV2) {
      final random = Random.secure();
      return Uint8List.fromList(List.generate(512, (_) => random.nextInt(256)));
    }
    await dataItem.sign(ArweaveSigner(inner));
    return utils.decodeBase64ToBytes(dataItem.signature);
  }
}

/// A [KeyValueStore] in memory: this device's preferences, for one test.
class MemoryKeyValueStore implements KeyValueStore {
  final values = <String, Object>{};

  @override
  Future<bool> putString(String key, String value) async {
    values[key] = value;
    return true;
  }

  @override
  String? getString(String key) => values[key] as String?;

  @override
  Future<bool> putBool(String key, bool value) async {
    values[key] = value;
    return true;
  }

  @override
  bool? getBool(String key) => values[key] as bool?;

  @override
  Future<bool> remove(String key) async => values.remove(key) != null;

  @override
  Set<String> getKeys() => values.keys.toSet();
}
