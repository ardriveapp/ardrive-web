@TestOn('browser')
library;

import 'dart:async';
// A browser test.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:js_util' as js_util;

import 'package:ardrive/drive_state_sqlite/artifact_sink.dart';
import 'package:ardrive/drive_state_sqlite/drive_state_artifact_export.dart'
    as sqlite;
import 'package:ardrive/models/database/web.dart';
import 'package:ardrive/models/database/web_artifact_vfs.dart';
import 'package:ardrive/models/database/web_worker/web_database_worker.dart';
import 'package:ardrive/models/models.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:sqlite3/wasm.dart';
import 'package:test/test.dart';

import '../../test_utils/schema_statements.dart';

/// The web database in a dedicated worker, on OPFS (docs/WEB_DATABASE.md),
/// exercised in a real browser.
///
/// Run with `tool/browser_tests.sh`, which compiles `web/db_worker.js` and
/// serves `web/` on 127.0.0.1:8099. A worker has to be same-origin with the
/// page, and this page is the test runner's, so each one starts from a blob
/// script that imports the served worker.
void main() {
  const served = 'http://127.0.0.1:8099';
  const sqlite3Url = '$served/sqlite3.wasm';
  var counter = 0;
  late String name;
  final workers = <WebDatabaseWorker>[];
  final databases = <Database>[];

  String workerUrl() => html.Url.createObjectUrlFromBlob(
      html.Blob(["importScripts('$served/db_worker.js');"], 'text/javascript'));

  WebDatabaseWorker startWorker() {
    final worker = WebDatabaseWorker.start(workerUrl());
    workers.add(worker);
    return worker;
  }

  Future<Database> openWriter(WebDatabaseWorker worker,
      {Uint8List? migrateFrom}) async {
    final opened = await worker.openWriter(name: name, sqlite3Url: sqlite3Url);
    expect(opened.isOpen, isTrue, reason: '${opened.failure} ${opened.error}');
    if (opened.needsMigration) await worker.migrate(migrateFrom);
    final db = Database(await worker.serve());
    databases.add(db);
    return db;
  }

  Future<void> removeOpfs(String dbName) async {
    final storage =
        js_util.getProperty<Object>(html.window.navigator, 'storage');
    final root = await js_util.promiseToFuture<Object>(
        js_util.callMethod(storage, 'getDirectory', []));
    try {
      final dir = await js_util.promiseToFuture<Object>(
          js_util.callMethod(root, 'getDirectoryHandle', ['ardrive-db']));
      await js_util
          .promiseToFuture<Object?>(js_util.callMethod(dir, 'removeEntry', [
        dbName,
        js_util.jsify({'recursive': true})
      ]));
    } catch (_) {}
  }

  Future<void> addDrive(Database db, String id) =>
      db.into(db.drives).insert(DrivesCompanion.insert(
            id: id,
            rootFolderId: '$id-root',
            ownerAddress: 'owner',
            name: 'a drive',
            privacy: 'public',
            lastBlockHeight: const Value(100),
          ));

  Future<int> driveCount(Database db) async =>
      (await db.select(db.drives).get()).length;

  setUp(() {
    counter++;
    name =
        'web_worker_test_${counter}_${DateTime.now().microsecondsSinceEpoch}';
  });

  tearDown(() async {
    for (final db in databases) {
      try {
        await db.close();
      } catch (_) {}
    }
    databases.clear();
    for (final worker in workers) {
      worker.terminate();
    }
    workers.clear();
    webDatabaseWorker = null;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await removeOpfs(name);
  });

  test('a new database is created, written, and found again after a reopen',
      () async {
    final first = startWorker();
    final opened = await first.openWriter(name: name, sqlite3Url: sqlite3Url);
    expect(opened.needsMigration, isTrue, reason: 'nothing was there');
    await first.migrate(null);
    final db = Database(await first.serve());
    await addDrive(db, 'drive-a');
    await db.close();

    final again = startWorker();
    final reopened = await again.openWriter(name: name, sqlite3Url: sqlite3Url);
    expect(reopened.isOpen, isTrue);
    expect(reopened.needsMigration, isFalse,
        reason: 'the migration ran once, and is never run over live data');
    final db2 = Database(await again.serve());
    databases.add(db2);
    expect(await driveCount(db2), 1);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('every column type comes back across the worker exactly as written',
      () async {
    final db = await openWriter(startWorker());
    // Every byte value, so an encoding that rewrites any of them shows.
    final bytes = Uint8List.fromList(List.generate(256, (i) => i));
    await db.into(db.profiles).insert(ProfilesCompanion.insert(
          id: 'profile',
          username: 'ünïcödé 名前 🔐',
          encryptedWallet: bytes,
          keySalt: Uint8List(0),
          walletPublicKey: 'public-key',
          encryptedPublicKey: Uint8List.fromList([0, 0, 255]),
          profileType: 1,
        ));
    final profile = await db.select(db.profiles).getSingle();
    expect(profile.username, 'ünïcödé 名前 🔐');
    expect(profile.encryptedWallet, bytes);
    expect(profile.keySalt, isEmpty);
    expect(profile.encryptedPublicKey, [0, 0, 255]);
    expect(profile.sourceWalletAddress, isNull);

    final created = DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000);
    await db.into(db.drives).insert(DrivesCompanion.insert(
          id: 'typed',
          rootFolderId: 'root',
          ownerAddress: 'owner',
          name: 'typed',
          privacy: 'private',
          encryptedKey: Value(bytes),
          keyEncryptionIv: Value(Uint8List.fromList([1, 2, 3])),
          driveKeyGenerated: const Value(false),
          isHidden: const Value(true),
          lastBlockHeight: const Value(9007199254740991),
          dateCreated: Value(created),
        ));
    final drive = await db.select(db.drives).getSingle();
    expect(drive.encryptedKey, bytes);
    expect(drive.keyEncryptionIv, [1, 2, 3]);
    expect(drive.driveKeyGenerated, isFalse);
    expect(drive.isHidden, isTrue);
    expect(drive.lastBlockHeight, 9007199254740991,
        reason: 'the largest integer JavaScript holds exactly');
    expect(drive.dateCreated, created);
    expect(drive.syncCursor, isNull);
    final real = await db.customSelect('SELECT 0.1 + 0.2 AS r').getSingle();
    expect(real.read<double>('r'), 0.1 + 0.2);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a live query refreshes for batched writes and for named custom ones',
      () async {
    final db = await openWriter(startWorker());
    final counts = <int>[];
    final sub =
        db.select(db.drives).watch().listen((r) => counts.add(r.length));
    addTearDown(sub.cancel);

    Future<void> until(int n) async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!counts.contains(n) && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(counts, contains(n));
    }

    await until(0);
    await db.batch((b) => b.insert(
        db.drives,
        DrivesCompanion.insert(
          id: 'batched',
          rootFolderId: 'r',
          ownerAddress: 'o',
          name: 'n',
          privacy: 'public',
        )));
    await until(1);
    await db.customUpdate(
      'INSERT INTO drives (id, rootFolderId, ownerAddress, name, privacy) '
      "VALUES ('custom', 'r', 'o', 'n', 'public')",
      updates: {db.drives},
      updateKind: UpdateKind.insert,
    );
    await until(2);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
      'a drive state artifact is built in the worker, read out, handed back '
      'and attached', () async {
    final worker = startWorker();
    final db = await openWriter(worker);
    webDatabaseWorker = worker;
    await addDrive(db, 'drive-x');

    final artifact = await sqlite.exportDriveState(
      db,
      driveId: 'drive-x',
      producer: 'ArDrive-App/test',
      sink: await createArtifactSink('worker-test'),
      blockEnd: 100,
    );
    expect(
        String.fromCharCodes(artifact.bytes.sublist(0, 15)), 'SQLite format 3');

    final source = await createArtifactSource('worker-test', artifact.bytes);
    await db.customStatement('ATTACH DATABASE ? AS a', [source.path]);
    final carried =
        await db.customSelect('SELECT id FROM a.drives').getSingle();
    await db.customStatement('DETACH DATABASE a');
    expect(carried.read<String>('id'), 'drive-x');

    await source.dispose();
    expect(await worker.readFile(source.path), isNull,
        reason: 'a received artifact is freed with its source');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('the file requests cannot reach the database or its journal', () async {
    final worker = startWorker();
    final db = await openWriter(worker);
    await addDrive(db, 'kept');

    for (final path in ['/database', '/database-journal']) {
      await expectLater(
        worker.putFile(path, Uint8List.fromList([0, 0, 0])),
        throwsA(isA<StateError>()),
        reason: path,
      );
      await expectLater(worker.deleteFile(path), throwsA(isA<StateError>()),
          reason: path);
      await expectLater(worker.readFile(path), throwsA(isA<StateError>()),
          reason: path);
    }
    expect(await driveCount(db), 1, reason: 'the database is untouched');
  }, timeout: const Timeout(Duration(minutes: 2)));

  group('migration', () {
    Future<Uint8List> appDatabaseBytes(String sourceName) async {
      final saved = name;
      name = sourceName;
      final db = await openWriter(startWorker());
      await addDrive(db, 'migrated-drive');
      await db.close();
      databases.remove(db);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final bytes = await readOpfsCopy(sourceName);
      name = saved;
      await removeOpfs(sourceName);
      return bytes!;
    }

    test('fills a new database from an older store, once', () async {
      final bytes = await appDatabaseBytes('$name-source');

      final worker = startWorker();
      final opened =
          await worker.openWriter(name: name, sqlite3Url: sqlite3Url);
      expect(opened.needsMigration, isTrue);
      final result = await worker.migrate(bytes);
      expect(result.migrated, isTrue);
      final db = Database(await worker.serve());
      databases.add(db);
      expect(await driveCount(db), 1);
      await db.close();

      final later = startWorker();
      final reopened =
          await later.openWriter(name: name, sqlite3Url: sqlite3Url);
      expect(reopened.needsMigration, isFalse);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('refuses bytes that are not a sound database, and starts fresh',
        () async {
      final worker = startWorker();
      await worker.openWriter(name: name, sqlite3Url: sqlite3Url);
      final garbage = Uint8List.fromList(List.filled(8192, 7));
      final result = await worker.migrate(garbage);
      expect(result.migrated, isFalse);
      expect(result.rejected, isTrue);
      final db = Database(await worker.serve());
      databases.add(db);
      expect(await driveCount(db), 0);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('reads #2197\'s IndexedDB store first, then sql.js', () async {
      final idbName = '$name-idb';
      final sqlite3 = await WasmSqlite3.loadFromUrl(Uri.parse(sqlite3Url));
      final fs = await IndexedDbFileSystem.open(dbName: idbName);
      final file = fs
          .xOpen(Sqlite3Filename('/db.sqlite'),
              SqlFlag.SQLITE_OPEN_CREATE | SqlFlag.SQLITE_OPEN_READWRITE)
          .file;
      file.xWrite(Uint8List.fromList([1, 2, 3]), 0);
      file.xClose();
      await fs.flush();
      await fs.close();
      addTearDown(() => IndexedDbFileSystem.deleteDatabase(idbName));
      expect(sqlite3, isNotNull);

      var legacyRead = false;
      final fromIdb = await readMigrationSource(
        indexedDbName: idbName,
        readLegacy: () async {
          legacyRead = true;
          return Uint8List.fromList([9]);
        },
      );
      expect(fromIdb, [1, 2, 3]);
      expect(legacyRead, isFalse);

      final fromLegacy = await readMigrationSource(
        indexedDbName: '$idbName-empty',
        readLegacy: () async => Uint8List.fromList([9]),
      );
      addTearDown(() => IndexedDbFileSystem.deleteDatabase('$idbName-empty'));
      expect(fromLegacy, [9]);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  test('a second tab is refused the files and works on a sound copy', () async {
    final writer = await openWriter(startWorker());
    await addDrive(writer, 'from-the-writer');

    final second = startWorker();
    final refused = await second.openWriter(name: name, sqlite3Url: sqlite3Url);
    expect(refused.failure, WorkerOpenFailure.busy);
    second.terminate();

    final opened = await openThroughWorker(
      scriptUrl: workerUrl(),
      name: name,
      sqlite3Url: sqlite3Url,
      isWriter: false,
      readMigrationSource: () async => null,
    );
    expect(opened, isNotNull);
    workers.add(opened!.worker);
    final copy = Database(opened.connection);
    databases.add(copy);
    expect(await driveCount(copy), 1);

    await addDrive(copy, 'only-in-the-copy');
    expect(await driveCount(writer), 1,
        reason: 'a session copy never writes to the real database');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a copy that is not a sound database is refused, not served', () async {
    final reader = startWorker();
    final opened = await reader.openReader(
      name: name,
      sqlite3Url: sqlite3Url,
      seed: Uint8List.fromList([
        ...'SQLite format 3\u0000'.codeUnits,
        ...List.filled(4096, 9),
      ]),
    );
    expect(opened.failure, WorkerOpenFailure.corrupt);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
      'a writer waits for files a departed worker still holds, as on a '
      'reload, rather than settling for a session copy', () async {
    // A worker that holds the files and goes away 600 ms into the next open:
    // what a reload looks like from the new page.
    final departing = startWorker();
    final held = await departing.openWriter(name: name, sqlite3Url: sqlite3Url);
    expect(held.isOpen, isTrue);
    Timer(const Duration(milliseconds: 600), departing.terminate);

    final opened = await openThroughWorker(
      scriptUrl: workerUrl(),
      name: name,
      sqlite3Url: sqlite3Url,
      isWriter: true,
      readMigrationSource: () async => null,
    );
    expect(opened, isNotNull);
    workers.add(opened!.worker);
    final db = Database(opened.connection);
    await addDrive(db, 'written-after-the-reload');
    await db.close();

    final later = await openWriter(startWorker());
    expect(await driveCount(later), 1,
        reason: 'the write went to the real database, not to a session copy');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a worker killed inside a transaction leaves a sound database',
      () async {
    final worker = startWorker();
    final db = await openWriter(worker);
    await addDrive(db, 'before');

    unawaited(db.transaction(() async {
      await db.customStatement(
        'INSERT INTO drives (id, rootFolderId, ownerAddress, name, privacy) '
        'WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n '
        'WHERE i < 300000) '
        "SELECT 'bulk-' || i, 'r', 'o', 'n', 'public' FROM n",
      );
    }).catchError((_) {}));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    worker.terminate();
    databases.remove(db);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // Through the app's own open, which waits for the killed worker's files.
    final reopened = await openThroughWorker(
      scriptUrl: workerUrl(),
      name: name,
      sqlite3Url: sqlite3Url,
      isWriter: true,
      readMigrationSource: () async => null,
    );
    expect(reopened, isNotNull);
    workers.add(reopened!.worker);
    final again = Database(reopened.connection);
    databases.add(again);
    final check = await again.customSelect('PRAGMA integrity_check').get();
    expect(check.single.data.values.single, 'ok');
    expect(await driveCount(again), anyOf(1, 300002),
        reason: 'all of the transaction or none of it');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
      'a worker killed while it creates the schema leaves a database the '
      'next start opens', () async {
    // How many schema statements a first start issues.
    final counter = SchemaStatements();
    final first = startWorker();
    await first.openWriter(name: name, sqlite3Url: sqlite3Url);
    await first.migrate(null);
    final counted = Database((await first.serve()).interceptWith(counter));
    databases.add(counted);
    await counted.customSelect('SELECT 1').get();
    final statements = counter.count;
    expect(statements, greaterThan(10));

    final base = name;
    // The first table, an index part way through, and the last statement.
    for (final n in [2, statements ~/ 2, statements]) {
      name = '$base-cut-$n';
      final worker = startWorker();
      final opened =
          await worker.openWriter(name: name, sqlite3Url: sqlite3Url);
      await worker.migrate(null);
      expect(opened.needsMigration, isTrue);
      final killed = Completer<void>();
      final cut = Database((await worker.serve()).interceptWith(
        SchemaStatements(
          at: n,
          instead: (_) {
            // A reload: the worker goes, with no chance to finish or roll
            // back, before statement n reaches it.
            worker.terminate();
            killed.complete();
            return Completer<void>().future;
          },
        ),
      ));
      unawaited(
          cut.customSelect('SELECT 1').get().then((_) {}, onError: (_) {}));
      await killed.future.timeout(const Duration(seconds: 30));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final reopened = await openThroughWorker(
        scriptUrl: workerUrl(),
        name: name,
        sqlite3Url: sqlite3Url,
        isWriter: true,
        readMigrationSource: () async => null,
      );
      expect(reopened, isNotNull);
      workers.add(reopened!.worker);
      final again = Database(reopened.connection);
      databases.add(again);
      // Throws, on the unfinished schema, where this start would have hung.
      await again.customSelect('SELECT 1').get();
      await addDrive(again, 'after-the-cut');
      expect(await driveCount(again), 1);
      final indexes = await again
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'index' "
              "AND name = 'idx_network_transactions_status'")
          .get();
      expect(indexes, hasLength(1));
      await again.close();
      databases.remove(again);
      await removeOpfs(name);
    }
    name = base;
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('deleting the local database removes every store, keeping a copy',
      () async {
    final worker = startWorker();
    final db = await openWriter(worker);
    await addDrive(db, 'before-the-reset');
    webDatabaseWorker = worker;

    final idbName = '$name-idb';
    final legacyName = '$name-legacy';
    for (final store in [idbName, legacyName]) {
      final fs = await IndexedDbFileSystem.open(dbName: store);
      fs
          .xOpen(Sqlite3Filename('/db.sqlite'),
              SqlFlag.SQLITE_OPEN_CREATE | SqlFlag.SQLITE_OPEN_READWRITE)
          .file
          .xClose();
      await fs.flush();
      await fs.close();
    }

    final deleted = await deleteLocalDatabase(
      opfsName: name,
      indexedDbName: idbName,
      legacyIndexedDbName: legacyName,
    );
    databases.remove(db);
    expect(deleted, isTrue);
    expect(webDatabaseWorker, isNull);

    final left = await IndexedDbFileSystem.databases();
    if (left != null) {
      expect(left, isNot(contains(idbName)));
      expect(left, isNot(contains(legacyName)));
    }

    // The copy kept beside it, then removed by this test.
    final storage =
        js_util.getProperty<Object>(html.window.navigator, 'storage');
    final root = await js_util.promiseToFuture<Object>(
        js_util.callMethod(storage, 'getDirectory', []));
    final parent = await js_util.promiseToFuture<Object>(
        js_util.callMethod(root, 'getDirectoryHandle', ['ardrive-db']));
    final names = <String>[];
    final entries = js_util.callMethod<Object>(parent, 'keys', []);
    while (true) {
      final next = await js_util
          .promiseToFuture<Object>(js_util.callMethod(entries, 'next', []));
      if (js_util.getProperty<bool>(next, 'done')) break;
      names.add(js_util.getProperty<String>(next, 'value'));
    }
    expect(names, isNot(contains(name)));
    final copies = names.where((n) => n.startsWith('$name-reset-')).toList();
    expect(copies, hasLength(1));
    for (final copy in copies) {
      await js_util.promiseToFuture<Object?>(
          js_util.callMethod(parent, 'removeEntry', [copy]));
    }

    final fresh = startWorker();
    final reopened = await fresh.openWriter(name: name, sqlite3Url: sqlite3Url);
    expect(reopened.needsMigration, isTrue, reason: 'it starts fresh');
    await fresh.migrate(null);
    final empty = Database(await fresh.serve());
    databases.add(empty);
    expect(await driveCount(empty), 0);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a worker script that does not load leaves the IndexedDB path',
      () async {
    final opened = await openThroughWorker(
      // Same-origin, as in the app, and missing: a build without the script.
      scriptUrl: html.Url.createObjectUrlFromBlob(html.Blob(
          ["importScripts('$served/no_such_worker.js');"], 'text/javascript')),
      name: name,
      sqlite3Url: sqlite3Url,
      isWriter: true,
      readMigrationSource: () async => null,
    );
    expect(opened, isNull);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
