import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/utils.dart';

/// "Remember on this device": a drive key is stored wrapped by the device
/// key, or kept for the session only, and "Forget on this device" moves a
/// stored key to memory. The next session starts with forgotten drives
/// locked.
void main() {
  const driveId = 'b3c8cb1b-4c3b-5d2c-9b3f-7e2b1c4d5e6f';
  const otherId = 'c4d9dc2c-5d4c-6e3d-ac4f-8f3c2d5e6f70';

  late Database db;
  late DriveDao dao;

  final deviceKey = SecretKey(List.filled(32, 7));
  final driveKey = DriveKey(SecretKey(List.filled(32, 3)), true);
  final otherKey = DriveKey(SecretKey(List.filled(32, 4)), true);

  DriveEntity entity(String id) => DriveEntity(
        id: id,
        name: 'drive $id',
        rootFolderId: 'root-$id',
        privacy: DrivePrivacyTag.private,
      )
        ..ownerAddress = 'owner'
        ..createdAt = DateTime(2026);

  Future<List<int>?> bytesOf(DriveKey? key) async =>
      key == null ? null : await key.key.extractBytes();

  Future<Drive> row(String id) => dao.driveById(driveId: id).getSingle();

  /// What a reload does to memory: a new session starts with none.
  Future<void> newSession() => dao.clearSessionMemory();

  setUp(() {
    db = getTestDb();
    dao = db.driveDao;
  });
  tearDown(() => db.close());

  test('a remembered key is stored, wrapped, and opens after a reload',
      () async {
    await dao.writeDriveEntity(
      name: 'drive',
      entity: entity(driveId),
      driveKey: driveKey,
      profileKey: deviceKey,
    );
    await newSession();

    expect((await row(driveId)).encryptedKey, isNotNull);
    expect(await bytesOf(await dao.getDriveKey(driveId, deviceKey)),
        await bytesOf(driveKey));
  });

  test('a key kept for the session is never written, and is gone after',
      () async {
    await dao.keepDriveKeyForSession(driveId: driveId, driveKey: driveKey);
    // The row is written afterwards by the unlock; it must stay empty.
    await dao.writeDriveEntity(
      name: 'drive',
      entity: entity(driveId),
      driveKey: driveKey,
      profileKey: deviceKey,
    );
    // And by a later discovery pass, which writes every drive it opened.
    await dao.updateUserDrives({entity(driveId): driveKey}, deviceKey);

    expect((await row(driveId)).encryptedKey, isNull);
    expect((await row(driveId)).keyEncryptionIv, isNull);
    expect(await dao.getStoredDriveKey(driveId, deviceKey), isNull);
    // This session still reads it, from memory.
    expect(await bytesOf(await dao.getDriveKey(driveId, deviceKey)),
        await bytesOf(driveKey));
    expect(await dao.forgottenDriveIds(), {driveId});

    await newSession();
    expect(await dao.getDriveKey(driveId, deviceKey), isNull);
  });

  test('remembering again stores the key and clears the mark', () async {
    await dao.keepDriveKeyForSession(driveId: driveId, driveKey: driveKey);
    await dao.allowRememberingDriveKey(driveId);
    await dao.writeDriveEntity(
      name: 'drive',
      entity: entity(driveId),
      driveKey: driveKey,
      profileKey: deviceKey,
    );

    expect((await row(driveId)).encryptedKey, isNotNull);
    expect(await dao.forgottenDriveIds(), isEmpty);
  });

  test('Forget on this device: open now, stored nowhere, locked next session',
      () async {
    await dao.writeDriveEntity(
      name: 'drive',
      entity: entity(driveId),
      driveKey: driveKey,
      profileKey: deviceKey,
    );
    final remembered = dao.watchDriveKeyRemembered(driveId);
    expect(await remembered.first, isTrue);

    expect(await dao.forgetDriveKey(driveId, deviceKey), isTrue);

    expect((await row(driveId)).encryptedKey, isNull);
    expect(await dao.watchDriveKeyRemembered(driveId).first, isFalse);
    expect(await bytesOf(await dao.getDriveKey(driveId, deviceKey)),
        await bytesOf(driveKey));
    // Nothing stored any more: forgetting again does nothing.
    expect(await dao.forgetDriveKey(driveId, deviceKey), isFalse);

    // The next session: the drive is detached, to come back as locked.
    await newSession();
    expect(await dao.detachForgottenDrives(), [driveId]);
    expect(await dao.driveById(driveId: driveId).getSingleOrNull(), isNull);
    expect(await dao.forgottenDriveIds(), {driveId},
        reason: 'the choice outlives the drive row');
  });

  test('a forgotten drive this session opened before signing in is kept',
      () async {
    await dao.keepDriveKeyForSession(driveId: driveId, driveKey: driveKey);
    await dao.writeDriveEntity(
      name: 'drive',
      entity: entity(driveId),
      driveKey: driveKey,
      profileKey: deviceKey,
    );

    expect(await dao.detachForgottenDrives(), isEmpty);
    expect(await dao.driveById(driveId: driveId).getSingleOrNull(), isNotNull);
  });

  test('Forget all on this device forgets every stored key', () async {
    for (final (id, key) in [(driveId, driveKey), (otherId, otherKey)]) {
      await dao.writeDriveEntity(
        name: 'drive',
        entity: entity(id),
        driveKey: key,
        profileKey: deviceKey,
      );
    }
    expect(await dao.watchRememberedDriveKeyCount().first, 2);
    expect((await dao.rememberedDriveIds()).toSet(), {driveId, otherId});

    expect(await dao.forgetAllDriveKeys(deviceKey), 2);

    expect(await dao.watchRememberedDriveKeyCount().first, 0);
    expect(await dao.forgottenDriveIds(), {driveId, otherId});
    expect(await bytesOf(await dao.getDriveKey(otherId, deviceKey)),
        await bytesOf(otherKey));
  });

  test('a key kept for the session is not stored at sign-in either', () async {
    await dao.writeDriveEntity(
        name: 'drive', entity: entity(driveId), driveKey: driveKey);
    await dao.keepDriveKeyForSession(driveId: driveId, driveKey: driveKey);

    expect(await dao.persistInMemoryDriveKeys(deviceKey), isEmpty);
    expect((await row(driveId)).encryptedKey, isNull);
  });

  test('another tab that is not signed in forgets without reading', () async {
    await dao.writeDriveEntity(
      name: 'drive',
      entity: entity(driveId),
      driveKey: driveKey,
      profileKey: deviceKey,
    );

    await dao.forgetStoredDriveKeyUnread(driveId);

    expect((await row(driveId)).encryptedKey, isNull);
    expect(await dao.forgottenDriveIds(), {driveId});
  });
}
