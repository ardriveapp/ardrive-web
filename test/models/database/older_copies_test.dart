import 'dart:convert';
import 'dart:io';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/database/database_helpers.dart';
import 'package:ardrive/models/models.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/utils.dart';

/// A profile in the format before 3.0 leaks the start of the wallet's JSON
/// to anyone who reads it. Once the profile is in the current format, every
/// older copy on the device goes, once: the older stores and reset copies,
/// and the free pages (`VACUUM`).
void main() {
  const password = 'correct horse battery staple';
  final wallet = getTestWallet();

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('older_copies'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// A format 1 profile as builds before 3.0 wrote it. Returns its
  /// encrypted wallet.
  Future<Uint8List> addFormat1Profile(Database db, {String? id}) async {
    final derived = await ArDriveCrypto().deriveProfileKey(password);
    final publicKey = await wallet.getOwner();
    final encryptedPublicKey = await aesGcm.encrypt(utf8.encode(publicKey),
        secretKey: derived.key, nonce: derived.salt);
    final encryptedWallet = (await aesGcm.encrypt(
            utf8.encode(json.encode(wallet.toJwk())),
            secretKey: derived.key,
            nonce: derived.salt))
        .concatenation(nonce: false);
    await db.into(db.profiles).insert(ProfilesCompanion.insert(
          id: id ?? await wallet.getAddress(),
          username: 'user.username',
          encryptedWallet: encryptedWallet,
          keySalt: Uint8List.fromList(derived.salt),
          profileType: ProfileType.json.index,
          walletPublicKey: publicKey,
          encryptedPublicKey: encryptedPublicKey.concatenation(nonce: false),
        ));
    return encryptedWallet;
  }

  bool fileHolds(File file, List<int> bytes) {
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

  test(
      'after the rewrite, no format 1 copy is left in the file, even one an '
      'older build deleted', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final file = File('${dir.path}/db.sqlite');
    final db = Database(NativeDatabase(file));
    addTearDown(db.close);

    // An earlier account, signed out by a build without secure_delete: its
    // encrypted wallet is in the free pages.
    final current = await addFormat1Profile(db);
    await db.customStatement('PRAGMA secure_delete = OFF');
    final earlier = await addFormat1Profile(db, id: 'earlier');
    await (db.delete(db.profiles)..where((p) => p.id.equals('earlier'))).go();
    await db.customStatement('PRAGMA secure_delete = ON');
    expect(fileHolds(file, earlier), isTrue);
    expect(fileHolds(file, current), isTrue);

    await db.profileDao.loadDefaultProfile(password);
    var deleted = 0;
    final cleared = await DatabaseHelpers(db).clearOlderCopies(
      ownsDatabase: true,
      deleteStores: () async {
        deleted++;
        return const [];
      },
    );

    expect(cleared, isTrue);
    expect(deleted, 1);
    expect(fileHolds(file, earlier), isFalse);
    expect(fileHolds(file, current), isFalse);
  });

  test('once: a second session clears nothing', () async {
    final db = getTestDb();
    addTearDown(db.close);
    await db.profileDao.addProfile('user', password, wallet, ProfileType.json);
    var deleted = 0;
    Future<List<String>> deleteStores() async {
      deleted++;
      return const [];
    }

    final helpers = DatabaseHelpers(db);
    expect(
        await helpers.clearOlderCopies(
            ownsDatabase: true, deleteStores: deleteStores),
        isTrue);
    expect(
        await helpers.clearOlderCopies(
            ownsDatabase: true, deleteStores: deleteStores),
        isFalse);
    expect(deleted, 1);
  });

  test('a tab on a session copy clears nothing, and leaves it to the owner',
      () async {
    final db = getTestDb();
    addTearDown(db.close);
    await db.profileDao.addProfile('user', password, wallet, ProfileType.json);
    var deleted = 0;

    expect(
      await DatabaseHelpers(db).clearOlderCopies(
        ownsDatabase: false,
        deleteStores: () async {
          deleted++;
          return const [];
        },
      ),
      isFalse,
    );
    expect(deleted, 0);
    expect(await db.profileDao.needsOlderCopiesCleared(), isTrue);
  });

  test('a store that would not go is tried again next session', () async {
    final db = getTestDb();
    addTearDown(db.close);
    await db.profileDao.addProfile('user', password, wallet, ProfileType.json);

    expect(
      await DatabaseHelpers(db).clearOlderCopies(
        ownsDatabase: true,
        deleteStores: () async => throw StateError('held by another tab'),
      ),
      isFalse,
    );
    expect(await db.profileDao.needsOlderCopiesCleared(), isTrue);
  });

  test('a profile still in format 1 is not cleared for yet', () async {
    final db = getTestDb();
    addTearDown(db.close);
    await addFormat1Profile(db);
    var deleted = 0;

    await DatabaseHelpers(db).clearOlderCopies(
      ownsDatabase: true,
      deleteStores: () async {
        deleted++;
        return const [];
      },
    );

    expect(deleted, 0);
  });
}
