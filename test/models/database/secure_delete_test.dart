import 'dart:io';

import 'package:ardrive/models/database/database_helpers.dart';
import 'package:ardrive/models/models.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

/// What sign-out deletes leaves the database file: `secure_delete` zeroes
/// deleted rows, and the VACUUM after sign-out drops the free pages earlier
/// builds left behind (docs/WEB_DATABASE.md, "Signing out").
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('secure_delete'));
  tearDown(() => dir.deleteSync(recursive: true));

  final marker =
      Uint8List.fromList(List.generate(4096, (i) => i.isEven ? 0xA5 : 0x5A));

  bool fileHolds(File file, Uint8List bytes) {
    final data = file.readAsBytesSync();
    final needle = bytes.sublist(0, 64);
    outer:
    for (var i = 0; i + needle.length <= data.length; i++) {
      for (var j = 0; j < needle.length; j++) {
        if (data[i + j] != needle[j]) continue outer;
      }
      return true;
    }
    return false;
  }

  Future<void> addProfile(Database db) =>
      db.into(db.profiles).insert(ProfilesCompanion.insert(
            id: 'address',
            username: 'user',
            encryptedWallet: marker,
            keySalt: Uint8List(16),
            walletPublicKey: 'public key',
            encryptedPublicKey: Uint8List(32),
            profileType: 0,
          ));

  test('every connection deletes securely', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = Database(NativeDatabase(File('${dir.path}/db.sqlite')));
    addTearDown(db.close);

    final row = await db.customSelect('PRAGMA secure_delete').getSingle();
    expect(row.data.values.single, 1);
  });

  test('a deleted profile is not left in the file', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final file = File('${dir.path}/db.sqlite');
    final db = Database(NativeDatabase(file));
    await addProfile(db);
    await db.customStatement('PRAGMA wal_checkpoint');
    expect(fileHolds(file, marker), isTrue);

    final helpers = DatabaseHelpers(db);
    await helpers.deleteAllTables();
    await helpers.wipeAfterSignOut();
    await db.close();

    expect(fileHolds(file, marker), isFalse);
  });

  test('a profile deleted before secure_delete existed goes at the VACUUM',
      () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final file = File('${dir.path}/db.sqlite');
    final db = Database(NativeDatabase(file));
    await addProfile(db);
    // As an earlier build deleted it: into the free pages.
    await db.customStatement('PRAGMA secure_delete = OFF');
    await db.delete(db.profiles).go();
    expect(fileHolds(file, marker), isTrue);

    await DatabaseHelpers(db).wipeAfterSignOut();
    await db.close();

    expect(fileHolds(file, marker), isFalse);
  });
}
