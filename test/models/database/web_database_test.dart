@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:ardrive/models/database/web.dart';
import 'package:drift/web.dart' show DriftWebStorage;
import 'package:sqlite3/wasm.dart';
import 'package:test/test.dart';

/// The sql.js handoff and the tab lock, run against a real IndexedDB.
///
/// Run with `tool/browser_tests.sh`, which CI runs too. It serves
/// `sqlite3.wasm` with CORS on 127.0.0.1:8099, because
/// `flutter test --platform chrome` serves only the compiled test bundle.
///
/// "A fresh page load" below means opening a new `IndexedDbFileSystem` on the
/// same database name, which sees only what reached IndexedDB.
void main() {
  late WasmSqlite3 sqlite3;
  var counter = 0;
  late String dbName;
  final opened = <IndexedDbFileSystem>[];

  /// A sql.js store that counts how often it is read. The handoff catches
  /// read errors by design, so a reader that threw would be swallowed rather
  /// than fail the test.
  var legacyReads = 0;
  Future<Uint8List?> countedRead() async {
    legacyReads++;
    return null;
  }

  Future<WasmSqlite3> loadSqlite3() => WasmSqlite3.loadFromUrl(
        Uri.parse('http://127.0.0.1:8099/sqlite3.wasm'),
      );

  setUpAll(() async {
    sqlite3 = await loadSqlite3();
  });

  setUp(() {
    legacyReads = 0;
    counter++;
    dbName = 'ardrive_web_db_test_${counter}_'
        '${DateTime.now().microsecondsSinceEpoch}';
  });

  tearDown(() async {
    for (final fs in opened) {
      await fs.close();
    }
    opened.clear();
    await IndexedDbFileSystem.deleteDatabase(dbName);
  });

  /// A real SQLite file holding one row, as sql.js would have stored it.
  Uint8List sqlJsDatabase(String row) {
    final vfs = InMemoryFileSystem(name: 'legacy-$counter-$row');
    sqlite3.registerVirtualFileSystem(vfs);
    final db = sqlite3.open('/legacy.sqlite', vfs: vfs.name);
    db.execute('CREATE TABLE t (x TEXT)');
    db.execute('INSERT INTO t VALUES (?)', [row]);
    db.dispose();
    sqlite3.unregisterVirtualFileSystem(vfs);
    return vfs.fileData['/legacy.sqlite']!;
  }

  /// The rows of table `t` in [bytes].
  List<String> rowsIn(Uint8List bytes) {
    final vfs = InMemoryFileSystem(name: 'read-$counter-${bytes.hashCode}');
    sqlite3.registerVirtualFileSystem(vfs);
    vfs.fileData['/read.sqlite'] = bytes;
    final db = sqlite3.open('/read.sqlite', vfs: vfs.name);
    try {
      return [for (final r in db.select('SELECT x FROM t')) r['x'] as String];
    } finally {
      db.dispose();
      sqlite3.unregisterVirtualFileSystem(vfs);
    }
  }

  Uint8List? readFile(VirtualFileSystem fs, String path) {
    if (fs.xAccess(path, 0) == 0) return null;
    final file =
        fs.xOpen(Sqlite3Filename(path), SqlFlag.SQLITE_OPEN_READONLY).file;
    try {
      final bytes = Uint8List(file.xFileSize());
      file.xRead(bytes, 0);
      return bytes;
    } finally {
      file.xClose();
    }
  }

  /// What a fresh page load would find in IndexedDB.
  Future<({Uint8List? database, bool marked})> afterReload() async {
    final fs = await IndexedDbFileSystem.open(dbName: dbName);
    opened.add(fs);
    return (
      database: readFile(fs, '/db.sqlite'),
      marked: fs.xAccess('/db.sqlite.from-sqljs', 0) != 0,
    );
  }

  Future<VirtualFileSystem> start({
    required Future<Uint8List?> Function() readLegacy,
    Future<bool> Function()? claimWriter,
    Future<void> Function(IndexedDbFileSystem, Uint8List)? promote,
    WasmSqlite3? engine,
  }) async {
    final fs = await openDatabaseFileSystem(
      engine ?? sqlite3,
      indexedDbName: dbName,
      readLegacy: readLegacy,
      claimWriter: claimWriter ?? () async => true,
      promote: promote,
    );
    if (fs is IndexedDbFileSystem) opened.add(fs);
    return fs;
  }

  group('the sql.js handoff', () {
    test('a user with nothing in sql.js starts fresh, and is never asked again',
        () async {
      final fs = await start(readLegacy: () async => null);

      expect(fs, isA<IndexedDbFileSystem>());
      expect((await afterReload()).marked, isTrue);

      await (fs as IndexedDbFileSystem).close();
      opened.remove(fs);
      final again = await start(readLegacy: countedRead);

      expect(again, isA<IndexedDbFileSystem>());
      expect(legacyReads, 0);
    });

    test('a sql.js database moves across and survives a page load', () async {
      final legacy = sqlJsDatabase('kept');

      final fs = await start(readLegacy: () async => legacy);

      expect(fs, isA<IndexedDbFileSystem>());
      final reloaded = await afterReload();
      expect(reloaded.marked, isTrue);
      expect(rowsIn(reloaded.database!), ['kept']);
    });

    test('a migrated database never sends the app back to sql.js', () async {
      final legacy = sqlJsDatabase('once');
      final first = await start(readLegacy: () async => legacy);
      await (first as IndexedDbFileSystem).close();
      opened.remove(first);

      final second = await start(readLegacy: countedRead);

      expect(second, isA<IndexedDbFileSystem>());
      expect(legacyReads, 0);
    });

    test(
        'a copy that fails to write keeps the user working this session, '
        'and the next start tries again', () async {
      final legacy = sqlJsDatabase('survives');

      final failed = await start(
        readLegacy: () async => legacy,
        promote: (_, __) async => throw StateError('quota exceeded'),
      );

      expect(failed, isNot(isA<IndexedDbFileSystem>()),
          reason: 'the session must not run on the half-made database');
      expect(rowsIn(readFile(failed, '/db.sqlite')!), ['survives'],
          reason: 'the session is seeded with the data it could not copy');
      final afterFailure = await afterReload();
      expect(afterFailure.marked, isFalse);
      expect(afterFailure.database, isNull);

      final retried = await start(readLegacy: () async => legacy);

      expect(retried, isA<IndexedDbFileSystem>());
      final afterRetry = await afterReload();
      expect(afterRetry.marked, isTrue);
      expect(rowsIn(afterRetry.database!), ['survives']);
    });

    test('a sql.js store that will not read is retried on the next start',
        () async {
      final legacy = sqlJsDatabase('later');

      final failed = await start(
        readLegacy: () async => throw StateError('IndexedDB said no'),
      );

      expect(failed, isNot(isA<IndexedDbFileSystem>()));
      expect((await afterReload()).marked, isFalse);

      final retried = await start(readLegacy: () async => legacy);

      expect(retried, isA<IndexedDbFileSystem>());
      expect(rowsIn((await afterReload()).database!), ['later']);
    });

    test('a corrupt sql.js store is settled once, not retried every start',
        () async {
      final corrupt = Uint8List.fromList([
        ...'SQLite format 3\u0000'.codeUnits,
        ...List.filled(4096, 7),
      ]);

      final fs = await start(readLegacy: () async => corrupt);

      expect(fs, isA<IndexedDbFileSystem>());
      final reloaded = await afterReload();
      expect(reloaded.marked, isTrue);
      expect(reloaded.database, isNull,
          reason: 'nothing corrupt is copied across; the user starts fresh');

      await (fs as IndexedDbFileSystem).close();
      opened.remove(fs);
      await start(readLegacy: countedRead);

      expect(legacyReads, 0);
    });

    test(
        'a store that opens but fails its integrity check is settled, '
        'not copied', () async {
      final damaged = sqlJsDatabase('first');
      // Many rows, so the table spans pages, then zero part of the cell
      // content at the end of page 3. SQLite still opens this file, which is
      // what makes it the dangerous kind of damage: only quick_check sees it.
      final vfs = InMemoryFileSystem(name: 'damage-$counter');
      sqlite3.registerVirtualFileSystem(vfs);
      vfs.fileData['/d.sqlite'] = damaged;
      final db = sqlite3.open('/d.sqlite', vfs: vfs.name);
      for (var i = 0; i < 300; i++) {
        db.execute('INSERT INTO t VALUES (?)', ['row $i ${'x' * 80}']);
      }
      db.dispose();
      final bytes = vfs.fileData['/d.sqlite']!;
      // Page size is a big-endian u16 at offset 16, where 1 means 65536.
      final raw = (bytes[16] << 8) | bytes[17];
      final pageSize = raw == 1 ? 65536 : raw;
      bytes.fillRange(3 * pageSize - 200, 3 * pageSize - 100, 0);
      final probe = sqlite3.open('/d.sqlite', vfs: vfs.name);
      final verdict = probe.select('PRAGMA quick_check').first.values.first;
      probe.dispose();
      sqlite3.unregisterVirtualFileSystem(vfs);
      expect(verdict, isNot('ok'),
          reason: 'precondition: the damage must open and fail the check '
              '(page size $pageSize, ${bytes.length} bytes)');

      final fs = await start(readLegacy: () async => bytes);

      expect(fs, isA<IndexedDbFileSystem>());
      final reloaded = await afterReload();
      expect(reloaded.marked, isTrue);
      expect(reloaded.database, isNull,
          reason: 'a damaged store is never copied across');
    });

    test('a longer file left by an earlier attempt is cut to the new size',
        () async {
      final legacy = sqlJsDatabase('fits');
      final leftover = await IndexedDbFileSystem.open(dbName: dbName);
      final file = leftover
          .xOpen(
            Sqlite3Filename('/db.sqlite'),
            SqlFlag.SQLITE_OPEN_CREATE | SqlFlag.SQLITE_OPEN_READWRITE,
          )
          .file;
      file.xWrite(Uint8List(legacy.length * 3), 0);
      file.xClose();
      await leftover.flush();
      await leftover.close();

      await start(readLegacy: () async => legacy);

      expect((await afterReload()).database!.length, legacy.length);
    });
  });

  group('the real sql.js store', () {
    /// Writes [bytes] exactly where and how the sql.js backend persisted
    /// itself, under a name of this test's own.
    Future<String> storeAsSqlJs(Uint8List bytes) async {
      final name = 'sqljs-$dbName';
      final storage = await DriftWebStorage.indexedDbIfSupported(name);
      await storage.open();
      await storage.store(bytes);
      await storage.close();
      return name;
    }

    test('is read back byte for byte', () async {
      final legacy = sqlJsDatabase('as stored');
      final name = await storeAsSqlJs(legacy);

      expect(await readSqlJsDatabase(name: name), legacy);
    });

    test('reads as nothing for a user who never had one', () async {
      expect(await readSqlJsDatabase(name: 'never-$dbName'), isNull);
    });

    test(
        'comes through the whole migration, and is still there afterwards '
        'for a rollback', () async {
      final legacy = sqlJsDatabase('through sql.js storage');
      final name = await storeAsSqlJs(legacy);

      final fs = await start(readLegacy: () => readSqlJsDatabase(name: name));

      expect(fs, isA<IndexedDbFileSystem>());
      final reloaded = await afterReload();
      expect(reloaded.marked, isTrue);
      expect(rowsIn(reloaded.database!), ['through sql.js storage']);
      expect(await readSqlJsDatabase(name: name), legacy,
          reason: 'the legacy copy is kept so a rolled-back build finds it');
    });
  });

  group('two tabs', () {
    test('the first claim on a lock wins and a second is refused', () async {
      final name = 'ardrive-lock-test-$counter';

      expect(await claimWriterLock(name), isTrue);
      expect(await claimWriterLock(name), isFalse);
    });

    test('a lock request that fails is treated as another tab owning it',
        () async {
      // The Web Locks spec reserves names starting with '-', so the browser
      // must reject this request: a real failure, not a simulated one.
      expect(await claimWriterLock('-reserved-$counter'), isFalse);
    });

    test(
        'a second tab works on a copy, and nothing it writes reaches the '
        'database the first tab owns', () async {
      final lock = 'ardrive-lock-tabs-$counter';
      final tabA = await loadSqlite3();
      final tabB = await loadSqlite3();

      final first = await start(
        engine: tabA,
        readLegacy: () async => null,
        claimWriter: () => claimWriterLock(lock),
      );
      expect(first, isA<IndexedDbFileSystem>());
      final dbA = tabA.open('/db.sqlite', vfs: first.name);
      dbA.execute('CREATE TABLE t (x TEXT)');
      dbA.execute("INSERT INTO t VALUES ('from the first tab')");
      dbA.dispose();
      await (first as IndexedDbFileSystem).flush();

      final second = await start(
        engine: tabB,
        readLegacy: countedRead,
        claimWriter: () => claimWriterLock(lock),
      );

      expect(second, isNot(isA<IndexedDbFileSystem>()));
      final dbB = tabB.open('/db.sqlite', vfs: second.name);
      expect(
        [for (final r in dbB.select('SELECT x FROM t')) r['x']],
        ['from the first tab'],
        reason: 'the copy starts from what the first tab had written',
      );
      dbB.execute("INSERT INTO t VALUES ('from the second tab')");
      dbB.dispose();

      expect(rowsIn((await afterReload()).database!), ['from the first tab']);
      expect(legacyReads, 0, reason: 'only the owning tab touches sql.js');
    });
  });
}
