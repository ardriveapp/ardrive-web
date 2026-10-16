/// The web database.
///
/// Uses `drift/wasm.dart` — sqlite3 compiled to WebAssembly — rather than the
/// `drift/web.dart` sql.js backend this app ran before. Two reasons, and the
/// second is the one that forced it:
///
///  * `drift/web.dart` is deprecated.
///  * `SqlJsDatabase.export()` returns `main` and nothing else, so an
///    *attached* database's bytes cannot be read back out. A drive state
///    artifact is built by attaching an empty database and copying rows into
///    it, so on sql.js it could be built and never retrieved.
///
/// **No worker, and no OPFS.** `WasmDatabase.open` would pick a storage tier
/// by probing the browser, and on both of this app's deployed origins that
/// probe answers `sharedIndexedDb` — OPFS needs cross-origin isolation, which
/// the permaweb build cannot have because its headers belong to whichever
/// gateway served it. `sharedIndexedDb` runs the database in a shared worker,
/// and this file runs it in the main isolate instead, where sql.js ran.
///
/// **That choice is drift's `unsafeIndexedDb` tier, and tabs are why it is
/// called unsafe.** `IndexedDbFileSystem` keeps its own in-memory copy of each
/// file per tab and writes 4 KiB blocks to the shared IndexedDB with no lock
/// across tabs, so two tabs writing at once interleave blocks of two diverged
/// databases into one corrupt file. sql.js wrote the whole database as one
/// blob, so two tabs only ever lost each other's updates. One tab therefore
/// owns the database through a Web Lock, and any other tab works on a private
/// copy that never reaches IndexedDB: see [openDatabaseFileSystem].
library;

import 'dart:async';
// Web-only: reached through the conditional import in database.dart.
// ignore: avoid_web_libraries_in_flutter
import 'dart:js_util' as js_util;

import 'package:ardrive/models/database/web_artifact_vfs.dart';
import 'package:ardrive/models/database/web_worker/web_database_worker.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:drift/web.dart' as legacy;
import 'package:flutter/foundation.dart';
import 'package:js/js.dart' show allowInterop;
import 'package:sqlite3/wasm.dart';

/// Where the database lives on the virtual filesystem, and the IndexedDB
/// database backing that filesystem. Both are named rather than defaulted so
/// the legacy handoff below can be reasoned about.
const _vfsDatabasePath = '/db.sqlite';
const _indexedDbName = 'ardrive_sqlite3';

/// Written once the sql.js handoff is settled, and checked instead of the
/// database file itself.
///
/// The database file cannot be the signal. drift creates it on open, so a
/// start whose migration failed would leave an empty one behind, and the next
/// start would read its presence as "already migrated" and never look at the
/// legacy store again.
const _migratedMarker = '$_vfsDatabasePath.from-sqljs';

/// The Web Lock that makes one tab the owner of the database.
const _writerLockName = 'ardrive-database';

/// The key the sql.js backend stored its bytes under, and the one thing that
/// must not change: it is where every existing user's database is.
const _legacyStorageName = 'db';

/// The worker script that holds the database on OPFS, and its database name
/// there. See docs/WEB_DATABASE.md.
const _workerScript = 'db_worker.js';
const _opfsDatabaseName = 'ardrive';

LazyDatabase openConnection() {
  return LazyDatabase(() async {
    // Claimed once, for the life of the tab, and shared by both paths below:
    // a second request from the same tab would find the lock taken.
    final isWriter = await claimWriterLock(_writerLockName);

    final viaWorker = await openThroughWorker(
      scriptUrl: _workerScript,
      name: _opfsDatabaseName,
      sqlite3Url: Uri.base.resolve('sqlite3.wasm').toString(),
      isWriter: isWriter,
      readMigrationSource: readMigrationSource,
      log: (message) => logger.i('[web-db] $message'),
    );
    if (viaWorker != null) {
      webDatabaseWorker = viaWorker.worker;
      logger.i('[web-db] the database is on OPFS, in a worker '
          '(${isWriter ? 'writer' : 'session copy'})');
      return viaWorker.connection;
    }

    logger.i('[web-db] the database is on IndexedDB, on this page');
    final sqlite3 = await WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.wasm'));
    final fs = await openDatabaseFileSystem(
      sqlite3,
      indexedDbName: _indexedDbName,
      readLegacy: readSqlJsDatabase,
      claimWriter: () async => isWriter,
    );

    webSqlite = (sqlite3: sqlite3, vfs: fs);

    // drift opens the database on the engine's default filesystem, which
    // openDatabaseFileSystem has set, and uses this one only to flush after
    // every write. A session copy has nowhere to flush to.
    return WasmDatabase(
      sqlite3: sqlite3,
      path: _vfsDatabasePath,
      fileSystem: fs is IndexedDbFileSystem ? fs : null,
    );
  });
}

/// The store a new OPFS database is filled from: #2197's IndexedDB database
/// if this browser has one, which supersedes sql.js where it exists, or
/// otherwise the sql.js database every earlier build kept.
@visibleForTesting
Future<Uint8List?> readMigrationSource({
  String indexedDbName = _indexedDbName,
  Future<Uint8List?> Function() readLegacy = readSqlJsDatabase,
}) async {
  final fs = await IndexedDbFileSystem.open(dbName: indexedDbName);
  try {
    final bytes = _readWholeFile(fs, _vfsDatabasePath);
    if (bytes != null && bytes.isNotEmpty) return bytes;
  } finally {
    await fs.close();
  }
  return readLegacy();
}

@visibleForTesting
Future<VirtualFileSystem> openDatabaseFileSystem(
  WasmSqlite3 sqlite3, {
  required String indexedDbName,
  required Future<Uint8List?> Function() readLegacy,
  required Future<bool> Function() claimWriter,
  Future<void> Function(IndexedDbFileSystem fs, Uint8List bytes)? promote,
}) async {
  final fs = await IndexedDbFileSystem.open(dbName: indexedDbName);

  if (!await claimWriter()) {
    logger.w('the database is open in another tab; this tab keeps a copy');
    final copy = _readWholeFile(fs, _vfsDatabasePath);
    await fs.close();
    return _sessionFileSystem(sqlite3, 'ardrive-other-tab', seed: copy);
  }

  final migration = await migrateFromSqlJsIfNeeded(
    sqlite3,
    fs,
    readLegacy: readLegacy,
    promote: promote ?? _promote,
  );
  if (migration.retryNextStart) {
    await fs.close();
    return _sessionFileSystem(
      sqlite3,
      'ardrive-this-session',
      seed: migration.sessionSeed,
    );
  }

  sqlite3.registerVirtualFileSystem(fs, makeDefault: true);
  return fs;
}

/// How the sql.js handoff ended.
///
/// [retryNextStart] means nothing was marked and the database file must not
/// be used this session. [sessionSeed] is the legacy data, when it was read
/// and proved sound, so that session can still show the user their drives.
@visibleForTesting
typedef SqlJsMigration = ({bool retryNextStart, Uint8List? sessionSeed});

/// Moves an existing sql.js database into the WASM filesystem, once.
///
/// The bytes sql.js stored *are* a SQLite file, so this is a byte-for-byte
/// handoff rather than a conversion: what comes out of the old storage goes
/// straight in as the new database, and drift's own migrations then run on it
/// exactly as they would have.
///
/// **The legacy copy is deliberately not deleted.** It costs the user some
/// disk and buys a way back: if this build has to be rolled back, the previous
/// one finds its database exactly where it left it.
///
/// **The marker is the commit point, and it is written last.** A failure that
/// could pass on another try (the legacy store would not read, the copy would
/// not write) leaves no marker, so the next start tries again from the legacy
/// store, which is untouched. A legacy store that is not a sound SQLite file
/// never will be, so that is marked as settled and the user starts fresh
/// rather than being retried forever.
@visibleForTesting
Future<SqlJsMigration> migrateFromSqlJsIfNeeded(
  WasmSqlite3 sqlite3,
  IndexedDbFileSystem fs, {
  required Future<Uint8List?> Function() readLegacy,
  required Future<void> Function(IndexedDbFileSystem fs, Uint8List bytes)
      promote,
}) async {
  const settled = (retryNextStart: false, sessionSeed: null);

  if (fs.xAccess(_migratedMarker, 0) != 0) return settled;

  final Uint8List? legacyBytes;
  try {
    legacyBytes = await readLegacy();
  } catch (e) {
    logger.w('could not read the sql.js database to migrate it: $e');
    return (retryNextStart: true, sessionSeed: null);
  }

  if (legacyBytes == null) {
    await _markMigrated(fs);
    return settled;
  }

  if (!_isSqliteFile(legacyBytes) || !_passesQuickCheck(sqlite3, legacyBytes)) {
    logger.w('the stored sql.js database is not a sound SQLite file; '
        'starting fresh');
    await _markMigrated(fs);
    return settled;
  }

  try {
    await promote(fs, legacyBytes);
    await _markMigrated(fs);
    logger
        .i('migrated ${legacyBytes.length} bytes from sql.js to sqlite3 wasm');
    return settled;
  } catch (e) {
    // Leave nothing half-written. The legacy copy is untouched and the
    // marker unwritten, so the next start tries again.
    logger.e('failed to migrate the sql.js database', e);
    //
    // Only a file that exists. `IndexedDbFileSystem` queues a delete for
    // IndexedDB, and the queued work for a file it never stored fails later,
    // outside this try, as an uncaught error from the storage layer.
    try {
      if (fs.xAccess(_vfsDatabasePath, 0) != 0) fs.xDelete(_vfsDatabasePath, 0);
    } catch (_) {}
    return (retryNextStart: true, sessionSeed: legacyBytes);
  }
}

/// Writes [bytes] as the database file and waits for IndexedDB to hold them.
///
/// `IndexedDbFileSystem` returns from a write before the write is stored. In
/// sqlite3 2.4.2 its queue stores work for different files in order, so the
/// marker [_markMigrated] creates next could not land before these bytes
/// anyway, and no test can tell this flush is here. It stays so that the
/// marker's meaning does not rest on the private ordering of a dependency's
/// queue: a tab closed during the first start must never keep a partial
/// database behind a marker that vouches for it.
Future<void> _promote(IndexedDbFileSystem fs, Uint8List bytes) async {
  final file = fs
      .xOpen(
        Sqlite3Filename(_vfsDatabasePath),
        SqlFlag.SQLITE_OPEN_CREATE | SqlFlag.SQLITE_OPEN_READWRITE,
      )
      .file;
  try {
    file.xWrite(bytes, 0);
    // An earlier attempt may have left a longer file here.
    file.xTruncate(bytes.length);
  } finally {
    file.xClose();
  }
  await fs.flush();
}

Future<void> _markMigrated(IndexedDbFileSystem fs) async {
  fs
      .xOpen(
        Sqlite3Filename(_migratedMarker),
        SqlFlag.SQLITE_OPEN_CREATE | SqlFlag.SQLITE_OPEN_READWRITE,
      )
      .file
      .xClose();
  await fs.flush();
}

bool _isSqliteFile(Uint8List bytes) {
  if (bytes.length < 16) return false;
  // The full 16-byte header, NUL included. A prefix check that stops at 15
  // accepts any sixteenth byte.
  const header = 'SQLite format 3\u0000';
  return String.fromCharCodes(bytes.sublist(0, 16)) == header;
}

/// Opens [bytes] on a scratch in-memory filesystem and asks SQLite whether
/// they hold together, before they become anything this app boots from.
bool _passesQuickCheck(WasmSqlite3 sqlite3, Uint8List bytes) {
  final scratch = InMemoryFileSystem(name: 'ardrive-migration-check');
  sqlite3.registerVirtualFileSystem(scratch);
  scratch.fileData['/check.sqlite'] = bytes;
  try {
    final db = sqlite3.open('/check.sqlite', vfs: scratch.name);
    try {
      final check = db.select('PRAGMA quick_check');
      return check.length == 1 && check.first.values.first == 'ok';
    } finally {
      db.dispose();
    }
  } catch (e) {
    logger.w('quick_check could not run on the sql.js database: $e');
    return false;
  } finally {
    sqlite3.unregisterVirtualFileSystem(scratch);
  }
}

/// An in-memory filesystem holding [seed] as the database, if there is one.
VirtualFileSystem _sessionFileSystem(
  WasmSqlite3 sqlite3,
  String name, {
  required Uint8List? seed,
}) {
  final session = InMemoryFileSystem(name: name);
  if (seed != null) session.fileData[_vfsDatabasePath] = seed;
  sqlite3.registerVirtualFileSystem(session, makeDefault: true);
  return session;
}

Uint8List? _readWholeFile(VirtualFileSystem fs, String path) {
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

/// Reads what the sql.js backend stored, through the same storage it used.
@visibleForTesting
Future<Uint8List?> readSqlJsDatabase({String name = _legacyStorageName}) async {
  final storage = await legacy.DriftWebStorage.indexedDbIfSupported(name);
  await storage.open();
  try {
    return await storage.restore();
  } finally {
    await storage.close();
  }
}

/// Claims [name] for the life of this tab, or reports that another tab holds
/// it.
///
/// A browser without Web Locks gets `true`: with nothing to coordinate
/// through, this tab behaves as every tab did before.
///
/// A request that *fails* gets `false`. Another tab may already own the
/// database, and owning it anyway is the one outcome here that can corrupt
/// it. A private copy only costs this session's changes; the user still sees
/// their data, and the next start asks again.
@visibleForTesting
Future<bool> claimWriterLock(String name) {
  final navigator =
      js_util.getProperty<Object?>(js_util.globalThis, 'navigator');
  final locks = navigator == null
      ? null
      : js_util.getProperty<Object?>(navigator, 'locks');
  if (locks == null) return Future.value(true);

  final granted = Completer<bool>();
  try {
    final request = js_util.callMethod<Object>(locks, 'request', [
      name,
      js_util.jsify({'ifAvailable': true}),
      allowInterop((Object? lock) {
        if (lock == null) {
          if (!granted.isCompleted) granted.complete(false);
          return null;
        }
        if (!granted.isCompleted) granted.complete(true);
        // Held until the tab goes away: a promise that never settles.
        return js_util.callConstructor<Object>(
          js_util.getProperty<Object>(js_util.globalThis, 'Promise'),
          [allowInterop((Object? resolve, Object? reject) {})],
        );
      }),
    ]);
    js_util.promiseToFuture<Object?>(request).catchError((Object e) {
      logger.w('the database lock request failed: $e');
      if (!granted.isCompleted) granted.complete(false);
      return null;
    });
  } catch (e) {
    logger.w('could not request the database lock: $e');
    if (!granted.isCompleted) granted.complete(false);
  }
  return granted.future;
}
