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
/// gateway served it. So the tier `open` would choose is IndexedDB-backed
/// anyway, and choosing it directly keeps the database in the main isolate,
/// which is exactly where the sql.js backend already ran. Same concurrency
/// story as today, on a supported engine.
library;

import 'package:ardrive/models/database/web_artifact_vfs.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:drift/web.dart' as legacy;
import 'package:sqlite3/wasm.dart';

/// Where the database lives on the virtual filesystem, and the IndexedDB
/// database backing that filesystem. Both are named rather than defaulted so
/// the legacy handoff below can be reasoned about.
const _vfsDatabasePath = '/db.sqlite';
const _indexedDbName = 'ardrive_sqlite3';

/// The key the sql.js backend stored its bytes under, and the one thing that
/// must not change: it is where every existing user's database is.
const _legacyStorageName = 'db';

LazyDatabase openConnection() {
  return LazyDatabase(() async {
    final sqlite3 = await WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.wasm'));
    final fs = await IndexedDbFileSystem.open(dbName: _indexedDbName);
    sqlite3.registerVirtualFileSystem(fs, makeDefault: true);

    await _migrateFromSqlJsIfNeeded(fs);

    webSqlite = (sqlite3: sqlite3, vfs: fs);

    return WasmDatabase(
      sqlite3: sqlite3,
      path: _vfsDatabasePath,
      fileSystem: fs,
    );
  });
}

/// Moves an existing sql.js database into the WASM filesystem, once.
///
/// The bytes sql.js stored *are* a SQLite file, so this is a byte-for-byte
/// handoff rather than a conversion: what comes out of the old storage goes
/// straight in as the new database, and drift's own migrations then run on it
/// exactly as they would have.
///
/// **The legacy copy is deliberately not deleted.** It costs the user some
/// disk and buys a way back: if this build has to be rolled back, the previous
/// one finds its database exactly where it left it. Deleting it would make the
/// migration one-way on the first run, which is not a property worth having
/// for the sake of a few megabytes.
///
/// Every failure here ends with the user on the login screen and their old
/// data still in place, never with a half-written database: nothing is written
/// unless a whole, plausible SQLite file was read.
Future<void> _migrateFromSqlJsIfNeeded(VirtualFileSystem fs) async {
  if (fs.xAccess(_vfsDatabasePath, 0) != 0) return;

  final Uint8List legacyBytes;
  try {
    final storage = await legacy.DriftWebStorage.indexedDbIfSupported(
      _legacyStorageName,
    );
    await storage.open();
    final restored = await storage.restore();
    await storage.close();
    if (restored == null) return;
    legacyBytes = restored;
  } catch (e) {
    logger.w('could not read the sql.js database to migrate it: $e');
    return;
  }

  if (legacyBytes.length < 16) return;

  // Anything that is not a SQLite file starts empty rather than opening a
  // broken database. An empty database is a login screen; a corrupt one is a
  // wedged app.
  if (String.fromCharCodes(legacyBytes.sublist(0, 15)) != 'SQLite format 3') {
    logger.w('the stored sql.js database is not a SQLite file; starting fresh');
    return;
  }

  try {
    final file = fs
        .xOpen(
          Sqlite3Filename(_vfsDatabasePath),
          SqlFlag.SQLITE_OPEN_CREATE | SqlFlag.SQLITE_OPEN_READWRITE,
        )
        .file;
    try {
      file.xWrite(legacyBytes, 0);
    } finally {
      file.xClose();
    }
    logger.i('migrated ${legacyBytes.length} bytes from sql.js to sqlite3 wasm');
  } catch (e) {
    // Leave nothing half-written: a partial database would be worse than none.
    logger.e('failed to migrate the sql.js database', e);
    try {
      fs.xDelete(_vfsDatabasePath, 0);
    } catch (_) {}
  }
}
