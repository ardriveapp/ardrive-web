import 'dart:convert';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/device_unlock/domain/device_key.dart';
import 'package:ardrive/device_unlock/domain/device_unlocker.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/utils.dart';

const _password = 'correct horse battery staple';

/// Writes a profile the way every build before 3.0 did: the wallet and the
/// public key under PBKDF2(password, salt), both with the salt as the nonce.
Future<SecretKey> _addFormat1Profile(
  Database db,
  Wallet wallet,
  ProfileType type,
) async {
  final derived = await ArDriveCrypto().deriveProfileKey(_password);
  final salt = derived.salt;
  final publicKey = await wallet.getOwner();

  final encryptedPublicKey = await aesGcm.encrypt(
    utf8.encode(publicKey),
    secretKey: derived.key,
    nonce: salt,
  );
  final encryptedWallet = type == ProfileType.json
      ? (await aesGcm.encrypt(
          utf8.encode(json.encode(wallet.toJwk())),
          secretKey: derived.key,
          nonce: salt,
        ))
          .concatenation(nonce: false)
      : Uint8List(0);

  await db.into(db.profiles).insert(ProfilesCompanion.insert(
        id: await wallet.getAddress(),
        username: 'user.username',
        encryptedWallet: encryptedWallet,
        keySalt: Uint8List.fromList(salt),
        profileType: type.index,
        walletPublicKey: publicKey,
        encryptedPublicKey: encryptedPublicKey.concatenation(nonce: false),
      ));

  return derived.key;
}

/// A private drive row whose key is wrapped by [wrapKey], as the drive DAO
/// writes it.
Future<void> _addDriveWithKey(
  Database db,
  String id,
  List<int> driveKey,
  SecretKey wrapKey,
) async {
  final box = await aesGcm.encrypt(driveKey, secretKey: wrapKey);
  await db.into(db.drives).insert(DrivesCompanion.insert(
        id: id,
        rootFolderId: 'root-$id',
        ownerAddress: 'owner',
        name: 'drive $id',
        privacy: 'private',
        encryptedKey: Value(box.concatenation(nonce: false)),
        keyEncryptionIv: Value(Uint8List.fromList(box.nonce)),
      ));
}

Future<List<int>> _unwrap(Database db, String id, SecretKey key) async {
  final row = await db.driveDao.driveById(driveId: id).getSingle();
  return aesGcm.decrypt(
    ArDriveCrypto().secretBoxFromDataWithMacConcatenation(
      row.encryptedKey!,
      nonce: row.keyEncryptionIv!,
    ),
    secretKey: key,
  );
}

void main() {
  late Database db;
  final wallet = getTestWallet();
  final driveKeyA = List.generate(32, (i) => i);
  final driveKeyB = List.generate(32, (i) => 255 - i);

  setUp(() => db = getTestDb());
  tearDown(() => db.close());

  group('a new profile', () {
    test('is in the current format, each value with its own nonce', () async {
      await db.profileDao
          .addProfile('user', _password, wallet, ProfileType.json);
      final row = await db.profileDao.defaultProfile().getSingle();

      expect(row.formatVersion, currentProfileFormat);
      expect(row.unlockMethod, 'password');
      expect(row.deviceSalt, hasLength(deviceSaltLength));
      expect(row.keyCheck, isNotNull);
      final nonces = {
        base64.encode(row.encryptedWallet.sublist(0, 12)),
        base64.encode(row.encryptedPublicKey.sublist(0, 12)),
        base64.encode(row.keyCheck!.sublist(0, 12)),
      };
      expect(nonces, hasLength(3), reason: 'no nonce is used twice');
      expect(nonces, isNot(contains(base64.encode(row.keySalt))));
    });

    test('opens with its password, and not with another', () async {
      final key = await db.profileDao
          .addProfile('user', _password, wallet, ProfileType.json);

      final loaded = await db.profileDao.loadDefaultProfile(_password);
      expect(await loaded.wallet.getAddress(), await wallet.getAddress());
      expect(await loaded.key.extractBytes(), await key.extractBytes());

      expect(
        () => db.profileDao.loadDefaultProfile('wrong'),
        throwsA(isA<ProfilePasswordIncorrectException>()),
      );
    });

    test('a second profile on another device gets another device salt',
        () async {
      await db.profileDao
          .addProfile('user', _password, wallet, ProfileType.json);
      final first = await db.profileDao.defaultProfile().getSingle();
      final other = getTestDb();
      addTearDown(other.close);
      await other.profileDao
          .addProfile('user', _password, wallet, ProfileType.json);
      final second = await other.profileDao.defaultProfile().getSingle();

      expect(second.deviceSalt, isNot(first.deviceSalt));
    });
  });

  group('a profile in the format before 3.0', () {
    for (final type in ProfileType.values) {
      test('${type.name}: is rewritten on unlock, drive keys and all',
          () async {
        final format1Key = await _addFormat1Profile(db, wallet, type);
        await _addDriveWithKey(db, 'a', driveKeyA, format1Key);
        await _addDriveWithKey(db, 'b', driveKeyB, format1Key);

        final loaded = await db.profileDao.loadDefaultProfile(_password);

        final row = await db.profileDao.defaultProfile().getSingle();
        expect(row.formatVersion, currentProfileFormat);
        expect(row.deviceSalt, hasLength(deviceSaltLength));
        expect(await loaded.wallet.getAddress(), await wallet.getAddress());
        expect(await loaded.key.extractBytes(),
            isNot(await format1Key.extractBytes()));

        // Every drive key now opens with the device key, and not the old one.
        expect(await _unwrap(db, 'a', loaded.key), driveKeyA);
        expect(await _unwrap(db, 'b', loaded.key), driveKeyB);
        expect(() => _unwrap(db, 'a', format1Key),
            throwsA(isA<SecretBoxAuthenticationError>()));

        // And the next unlock reads the new format with the same key.
        final again = await db.profileDao.loadDefaultProfile(_password);
        expect(await again.key.extractBytes(), await loaded.key.extractBytes());
        if (type == ProfileType.json) {
          expect(again.wallet.toJwk(), wallet.toJwk());
        }
      });
    }

    test('a wrong password is still a wrong password, and rewrites nothing',
        () async {
      await _addFormat1Profile(db, wallet, ProfileType.json);

      await expectLater(
        db.profileDao.loadDefaultProfile('wrong'),
        throwsA(isA<ProfilePasswordIncorrectException>()),
      );
      expect(
          (await db.profileDao.defaultProfile().getSingle()).formatVersion, 1);
    });

    test('a rewrite that fails keeps the old profile, which still opens',
        () async {
      final format1Key = await _addFormat1Profile(db, wallet, ProfileType.json);
      await _addDriveWithKey(db, 'a', driveKeyA, format1Key);
      final before = await db.profileDao.defaultProfile().getSingle();
      // The profile row refuses the rewrite, as a full disk or a closed tab
      // would stop it.
      await db.customStatement('''
        CREATE TRIGGER refuse BEFORE UPDATE ON profiles
        BEGIN SELECT RAISE(ABORT, 'refused'); END''');

      final loaded = await db.profileDao.loadDefaultProfile(_password);

      final after = await db.profileDao.defaultProfile().getSingle();
      expect(after.formatVersion, 1);
      expect(after.encryptedWallet, before.encryptedWallet);
      expect(after.deviceSalt, isNull);
      expect(await loaded.key.extractBytes(), await format1Key.extractBytes());
      expect(await loaded.wallet.getAddress(), await wallet.getAddress());
      // The drive keys were rewrapped inside the same transaction, so they
      // rolled back with it and still open with the old key.
      expect(await _unwrap(db, 'a', format1Key), driveKeyA);

      // Once the obstacle is gone, the next unlock rewrites it.
      await db.customStatement('DROP TRIGGER refuse');
      final later = await db.profileDao.loadDefaultProfile(_password);
      expect((await db.profileDao.defaultProfile().getSingle()).formatVersion,
          currentProfileFormat);
      expect(await _unwrap(db, 'a', later.key), driveKeyA);
    });

    test('a drive key the old key cannot open stops the rewrite', () async {
      final format1Key = await _addFormat1Profile(db, wallet, ProfileType.json);
      await _addDriveWithKey(db, 'a', driveKeyA, format1Key);
      await _addDriveWithKey(
          db, 'corrupt', driveKeyB, SecretKey(List.filled(32, 7)));

      final loaded = await db.profileDao.loadDefaultProfile(_password);

      expect(
          (await db.profileDao.defaultProfile().getSingle()).formatVersion, 1);
      expect(await _unwrap(db, 'a', loaded.key), driveKeyA);
    });
  });

  group('a profile unlocked by a wallet', () {
    Future<(SecretKey, DeviceRecord)> deviceKeyFrom(List<int> signature,
        {DeviceRecord? record}) async {
      final r = record ??
          DeviceRecord(
              method: DeviceUnlockMethod.wander, deviceSalt: newDeviceSalt());
      final key = await deriveDeviceKey(
          secret: signature, deviceSalt: r.deviceSalt, method: r.method);
      return (
        key,
        DeviceRecord(
          method: r.method,
          deviceSalt: r.deviceSalt,
          keyCheck: r.keyCheck ?? await makeKeyCheck(key),
        )
      );
    }

    test('opens with the same signature, and fails cleanly with another',
        () async {
      final (key, record) = await deviceKeyFrom([1, 2, 3]);
      await db.profileDao.addProfileWithDeviceKey(
        wallet: wallet,
        profileType: ProfileType.json,
        record: record,
        deviceKey: key,
      );

      final loaded = await db.profileDao.loadDefaultProfileWithDeviceKey(key);
      expect(loaded.wallet.toJwk(), wallet.toJwk());
      final stored = await db.profileDao.deviceRecord();
      expect(stored!.method, DeviceUnlockMethod.wander);
      expect(stored.deviceSalt, record.deviceSalt);

      final (otherKey, _) = await deviceKeyFrom([9, 9, 9], record: record);
      await expectLater(
        db.profileDao.loadDefaultProfileWithDeviceKey(otherKey),
        throwsA(isA<DeviceKeyMismatchException>()),
      );
      await expectLater(
        db.profileDao.loadDefaultProfile('any password'),
        throwsA(isA<ProfileUnlockMethodException>()),
      );
    });
  });
}
