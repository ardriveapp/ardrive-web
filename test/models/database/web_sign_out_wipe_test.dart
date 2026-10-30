@TestOn('browser')
library;

// A browser test.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:js_util' as js_util;
import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/database/database_helpers.dart';
import 'package:ardrive/models/database/web.dart';
import 'package:ardrive/models/database/web_artifact_vfs.dart';
import 'package:ardrive/models/database/web_worker/web_database_worker.dart';
import 'package:ardrive/models/models.dart';
import 'package:sqlite3/wasm.dart';
import 'package:test/test.dart';

import '../../test_utils/test_wallet.dart';

/// Sign-out on the web: the copies of the database older builds left are
/// deleted by the tab that owns the database, and what sign-out deletes from
/// the database itself is gone from the OPFS file (docs/WEB_DATABASE.md,
/// "Signing out").
///
/// Run with `tool/browser_tests.sh`, which serves `web/` on 127.0.0.1:8099.
void main() {
  const served = 'http://127.0.0.1:8099';
  var counter = 0;
  late String name;
  late String sqlJsStore;
  late String idbStore;

  Future<Object> opfsDir() async {
    final storage =
        js_util.getProperty<Object>(html.window.navigator, 'storage');
    final root = await js_util.promiseToFuture<Object>(
        js_util.callMethod(storage, 'getDirectory', []));
    return js_util.promiseToFuture<Object>(
        js_util.callMethod(root, 'getDirectoryHandle', [
      'ardrive-db',
      js_util.jsify({'create': true})
    ]));
  }

  Future<void> writeOpfsFile(String file, List<int> bytes) async {
    final dir = await opfsDir();
    final handle = await js_util
        .promiseToFuture<Object>(js_util.callMethod(dir, 'getFileHandle', [
      file,
      js_util.jsify({'create': true})
    ]));
    final writable = await js_util.promiseToFuture<Object>(
        js_util.callMethod(handle, 'createWritable', []));
    await js_util.promiseToFuture<Object?>(
        js_util.callMethod(writable, 'write', [Uint8List.fromList(bytes)]));
    await js_util
        .promiseToFuture<Object?>(js_util.callMethod(writable, 'close', []));
  }

  Future<bool> opfsHas(String entry) async {
    final dir = await opfsDir();
    for (final kind in ['getFileHandle', 'getDirectoryHandle']) {
      try {
        await js_util
            .promiseToFuture<Object>(js_util.callMethod(dir, kind, [entry]));
        return true;
      } catch (_) {}
    }
    return false;
  }

  Future<void> makeIndexedDbStore(String store) async {
    final fs = await IndexedDbFileSystem.open(dbName: store);
    final file = fs
        .xOpen(Sqlite3Filename('/db.sqlite'),
            SqlFlag.SQLITE_OPEN_CREATE | SqlFlag.SQLITE_OPEN_READWRITE)
        .file;
    file.xWrite(Uint8List.fromList([1, 2, 3]), 0);
    file.xClose();
    await fs.flush();
    await fs.close();
  }

  Future<void> removeOpfs(String entry) async {
    try {
      final dir = await opfsDir();
      await js_util
          .promiseToFuture<Object?>(js_util.callMethod(dir, 'removeEntry', [
        entry,
        js_util.jsify({'recursive': true})
      ]));
    } catch (_) {}
  }

  setUp(() async {
    counter++;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    name = 'wipe_test_${counter}_$stamp';
    sqlJsStore = 'wipe_test_sqljs_${counter}_$stamp';
    idbStore = 'wipe_test_idb_${counter}_$stamp';
    await makeIndexedDbStore(sqlJsStore);
    await makeIndexedDbStore(idbStore);
    await writeOpfsFile('$name-reset-1761000000000', [9, 9, 9]);
    await writeOpfsFile('$name-reset-1761000000001', [8, 8, 8]);
    // The live database's directory, and a file that only looks alike.
    await writeOpfsFile('$name-keep', [7]);
  });

  tearDown(() async {
    for (final store in [sqlJsStore, idbStore]) {
      try {
        await IndexedDbFileSystem.deleteDatabase(store);
      } catch (_) {}
    }
    for (final entry in [
      '$name-reset-1761000000000',
      '$name-reset-1761000000001',
      '$name-keep',
      name,
    ]) {
      await removeOpfs(entry);
    }
  });

  Future<List<String>> wipe({required bool isWriter, required bool onOpfs}) =>
      deleteLegacyLocalStores(
        opfsName: name,
        indexedDbName: idbStore,
        legacyIndexedDbName: sqlJsStore,
        isWriter: isWriter,
        onOpfs: onOpfs,
      );

  test('the tab that owns the database deletes every older copy', () async {
    final deleted = await wipe(isWriter: true, onOpfs: true);

    expect(
      deleted.toSet(),
      {
        sqlJsStore,
        idbStore,
        '$name-reset-1761000000000',
        '$name-reset-1761000000001',
      },
    );
    expect(await indexedDbExists(sqlJsStore), isFalse);
    expect(await indexedDbExists(idbStore), isFalse);
    expect(await opfsHas('$name-reset-1761000000000'), isFalse);
    expect(await opfsHas('$name-reset-1761000000001'), isFalse);
    expect(await opfsHas('$name-keep'), isTrue);
  });

  test('a tab working on a session copy deletes nothing', () async {
    expect(await wipe(isWriter: false, onOpfs: true), isEmpty);

    expect(await indexedDbExists(sqlJsStore), isTrue);
    expect(await indexedDbExists(idbStore), isTrue);
    expect(await opfsHas('$name-reset-1761000000000'), isTrue);
  });

  test('on the IndexedDB path, its store is the database and stays', () async {
    final deleted = await wipe(isWriter: true, onOpfs: false);

    expect(deleted, isNot(contains(idbStore)));
    expect(await indexedDbExists(idbStore), isTrue);
    expect(await indexedDbExists(sqlJsStore), isFalse);
  });

  test(
      'what sign-out deletes is gone from the OPFS file: secure_delete and '
      'VACUUM', () async {
    final worker = WebDatabaseWorker.start(html.Url.createObjectUrlFromBlob(
        html.Blob(
            ["importScripts('$served/db_worker.js');"], 'text/javascript')));
    addTearDown(() {
      worker.terminate();
      webDatabaseWorker = null;
    });
    final opened =
        await worker.openWriter(name: name, sqlite3Url: '$served/sqlite3.wasm');
    expect(opened.isOpen, isTrue, reason: '${opened.failure}');
    if (opened.needsMigration) await worker.migrate(null);
    final db = Database(await worker.serve());

    // A recognisable stand-in for an encrypted wallet.
    final marker =
        Uint8List.fromList(List.generate(4096, (i) => i.isEven ? 0xA5 : 0x5A));
    await db.into(db.profiles).insert(ProfilesCompanion.insert(
          id: 'address',
          username: 'user',
          encryptedWallet: marker,
          keySalt: Uint8List(16),
          walletPublicKey: 'public key',
          encryptedPublicKey: Uint8List(32),
          profileType: 0,
        ));
    final secureDelete =
        await db.customSelect('PRAGMA secure_delete').getSingle();
    expect(secureDelete.data.values.single, 1);
    expect(_contains((await readOpfsCopy(name))!, marker), isTrue,
        reason: 'the row is in the file before sign-out');

    final helpers = DatabaseHelpers(db);
    await helpers.deleteAllTables();
    await helpers.wipeAfterSignOut();
    await db.close();

    expect(
        _contains((await readOpfsCopy(name)) ?? Uint8List(0), marker), isFalse);
  });

  test(
      'once the profile is rewritten from format 1, its older copies go: the '
      'stores, the reset copies, and every format 1 byte in the OPFS file',
      () async {
    final worker = WebDatabaseWorker.start(html.Url.createObjectUrlFromBlob(
        html.Blob(
            ["importScripts('$served/db_worker.js');"], 'text/javascript')));
    addTearDown(() {
      worker.terminate();
      webDatabaseWorker = null;
    });
    final opened =
        await worker.openWriter(name: name, sqlite3Url: '$served/sqlite3.wasm');
    expect(opened.isOpen, isTrue, reason: '${opened.failure}');
    if (opened.needsMigration) await worker.migrate(null);
    final db = Database(await worker.serve());

    const password = 'a password';
    final wallet = getTestWallet();
    // The format 1 profile, as builds before 3.0 wrote it.
    final derived = await ArDriveCrypto().deriveProfileKey(password);
    final publicKey = await wallet.getOwner();
    final format1Wallet = (await aesGcm.encrypt(
            utf8.encode(json.encode(wallet.toJwk())),
            secretKey: derived.key,
            nonce: derived.salt))
        .concatenation(nonce: false);
    await db.into(db.profiles).insert(ProfilesCompanion.insert(
          id: await wallet.getAddress(),
          username: 'user',
          encryptedWallet: format1Wallet,
          keySalt: Uint8List.fromList(derived.salt),
          profileType: 0,
          walletPublicKey: publicKey,
          encryptedPublicKey: (await aesGcm.encrypt(utf8.encode(publicKey),
                  secretKey: derived.key, nonce: derived.salt))
              .concatenation(nonce: false),
        ));
    expect(_contains((await readOpfsCopy(name))!, format1Wallet), isTrue);

    await db.profileDao.loadDefaultProfile(password);
    final cleared = await DatabaseHelpers(db).clearOlderCopies(
      ownsDatabase: true,
      deleteStores: () => wipe(isWriter: true, onOpfs: true),
    );
    await db.close();

    expect(cleared, isTrue);
    expect(await indexedDbExists(sqlJsStore), isFalse);
    expect(await indexedDbExists(idbStore), isFalse);
    expect(await opfsHas('$name-reset-1761000000000'), isFalse);
    expect(_contains((await readOpfsCopy(name)) ?? Uint8List(0), format1Wallet),
        isFalse);
  });
}

/// Whether [bytes] holds the first 64 bytes of [marker] anywhere.
bool _contains(Uint8List bytes, Uint8List marker) {
  final needle = marker.sublist(0, 64);
  outer:
  for (var i = 0; i + needle.length <= bytes.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (bytes[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}
