import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/utils.dart';

/// A private drive opened without a profile has its key in memory only. Once
/// the user signs in, the key is encrypted onto the row with the profile key,
/// so the drive survives a reload and the sync finds the key where it looks
/// for a signed-in user.
void main() {
  const privateDriveId = 'b3c8cb1b-4c3b-5d2c-9b3f-7e2b1c4d5e6f';
  const publicDriveId = 'a2b7ba0a-3b2a-4c1b-8a2f-6d1a0b3c4d5e';
  const keptDriveId = 'c4d9dc2c-5d4c-6e3d-ac4f-8f3c2d5e6f70';
  const rootFolderId = 'e6fbfe4e-7f6e-8a5f-ce6f-af5e4f7a8b92';

  late Database db;
  late DriveDao dao;

  final profileKey = SecretKey(List.filled(32, 7));
  final visitorKey = DriveKey(SecretKey(List.filled(32, 3)), true);

  Future<void> insertDrive(String id, String privacy) =>
      db.into(db.drives).insert(DrivesCompanion.insert(
            id: id,
            rootFolderId: rootFolderId,
            ownerAddress: 'someone-else',
            name: 'drive $id',
            privacy: privacy,
          ));

  Future<List<int>> bytesOf(DriveKey? key) async =>
      key == null ? const [] : await key.key.extractBytes();

  setUp(() async {
    db = getTestDb();
    dao = db.driveDao;

    await insertDrive(privateDriveId, DrivePrivacyTag.private);
    await insertDrive(publicDriveId, DrivePrivacyTag.public);
  });

  tearDown(() => db.close());

  test('a private key held in memory is encrypted onto the row at sign-in',
      () async {
    await dao.putDriveKeyInMemory(
        driveID: privateDriveId, driveKey: visitorKey);

    final written = await dao.persistInMemoryDriveKeys(profileKey);

    expect(written, [privateDriveId]);

    final row = await dao.driveById(driveId: privateDriveId).getSingle();
    expect(row.encryptedKey, isNotNull);
    expect(row.keyEncryptionIv, isNotNull);

    // And it decrypts back to the key the visitor pasted.
    final read = await dao.getDriveKey(privateDriveId, profileKey);
    expect(await bytesOf(read), await bytesOf(visitorKey));
  });

  test(
      'a public drive and a private drive with no key in memory are left '
      'alone', () async {
    final written = await dao.persistInMemoryDriveKeys(profileKey);

    expect(written, isEmpty);

    final private = await dao.driveById(driveId: privateDriveId).getSingle();
    final public = await dao.driveById(driveId: publicDriveId).getSingle();
    expect(private.encryptedKey, isNull);
    expect(public.encryptedKey, isNull);
  });

  test('a row that already has its key is not rewritten', () async {
    final otherKey = DriveKey(SecretKey(List.filled(32, 9)), true);

    await insertDrive(keptDriveId, DrivePrivacyTag.private);
    await dao.putDriveKeyInMemory(driveID: keptDriveId, driveKey: otherKey);
    await dao.persistInMemoryDriveKeys(profileKey);

    final before = await dao.driveById(driveId: keptDriveId).getSingle();

    // A different key in memory now, as if the row had been attached by the
    // signed-in user and the vault held something stale.
    await dao.putDriveKeyInMemory(driveID: keptDriveId, driveKey: visitorKey);
    final written = await dao.persistInMemoryDriveKeys(profileKey);

    expect(written, isEmpty);

    final after = await dao.driveById(driveId: keptDriveId).getSingle();
    expect(after.encryptedKey, before.encryptedKey);
  });

  test(
      'a signed-in read of a private row with no encrypted key stays null, '
      'even with a key in memory', () async {
    // The sync relies on this: a private row with no key is how it knows it
    // has nothing to open an artifact with. Persisting at login is what makes
    // the visitor's key reachable, not a fallback here.
    await dao.putDriveKeyInMemory(
        driveID: privateDriveId, driveKey: visitorKey);

    expect(await dao.getDriveKey(privateDriveId, profileKey), isNull);
  });

  test('a public row has no key, in memory or anywhere', () async {
    expect(await dao.getDriveKey(publicDriveId, profileKey), isNull);
  });
}
