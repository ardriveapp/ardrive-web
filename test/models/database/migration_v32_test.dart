import 'dart:io';

import 'package:ardrive/models/models.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:test/test.dart';

/// Schema 32 adds the 3.0 local profile format's columns and the
/// `forgotten_drives` table. A saved profile keeps its format 1 until its
/// next unlock rewrites it (ProfileDao).
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('migration_v32'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// [halfUpgraded]: what a cut after the first new column would have left
  /// had the upgrade not been one transaction.
  Future<File> version31({bool halfUpgraded = false}) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final file = File('${dir.path}/db.sqlite');
    final created = Database(NativeDatabase(file));
    await created.customStatement('DROP TABLE profiles');
    await created.customStatement('DROP TABLE forgotten_drives');
    await created.customStatement('''
      CREATE TABLE profiles (
        id TEXT NOT NULL PRIMARY KEY, username TEXT NOT NULL,
        encryptedWallet BLOB NOT NULL, keySalt BLOB NOT NULL,
        walletPublicKey TEXT NOT NULL, encryptedPublicKey BLOB NOT NULL,
        profileType INTEGER NOT NULL, sourceWalletAddress TEXT
        ${halfUpgraded ? ', formatVersion INTEGER NOT NULL DEFAULT 1' : ''})''');
    await created.customStatement('''
      INSERT INTO profiles (id, username, encryptedWallet, keySalt,
        walletPublicKey, encryptedPublicKey, profileType) VALUES
        ('address', 'user', x'01', x'02', 'public key', x'03', 0)''');
    await created.customStatement('PRAGMA user_version = 31');
    await created.close();
    return file;
  }

  test('a version 31 database keeps its profile, in format 1', () async {
    final upgraded = Database(NativeDatabase(await version31()));
    addTearDown(upgraded.close);

    final profile = await upgraded.select(upgraded.profiles).getSingle();
    expect(profile.id, 'address');
    expect(profile.formatVersion, 1);
    expect(profile.deviceSalt, isNull);
    expect(profile.unlockMethod, isNull);
    expect(profile.keyCheck, isNull);
    expect(await upgraded.driveDao.forgottenDriveIds(), isEmpty);
    expect(
      (await upgraded.customSelect('PRAGMA user_version').getSingle())
          .data
          .values
          .single,
      32,
    );
  });

  test('an upgrade cut short and run again finishes', () async {
    final upgraded =
        Database(NativeDatabase(await version31(halfUpgraded: true)));
    addTearDown(upgraded.close);

    final profile = await upgraded.select(upgraded.profiles).getSingle();
    expect(profile.formatVersion, 1);
    expect(profile.keyCheck, isNull);
  });
}
