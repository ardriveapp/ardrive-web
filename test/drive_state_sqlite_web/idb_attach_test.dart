@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:sqlite3/wasm.dart';
import 'package:test/test.dart';

/// `ATTACH` against the filesystem the app actually runs.
///
/// The earlier probe used `InMemoryFileSystem`, which is a plain map. Production
/// uses `IndexedDbFileSystem`, which is that map plus a queue of asynchronous
/// writes back to IndexedDB — and SQLite's VFS entry points are synchronous. A
/// second database attached through it is the case that was never executed.
void main() {
  test('a second database can be attached, written, detached and read back',
      () async {
    final sqlite = await WasmSqlite3.loadFromUrl(
      Uri.parse('http://127.0.0.1:8099/sqlite3.wasm'),
    );
    final fs = await IndexedDbFileSystem.open(dbName: 'attach_probe');
    sqlite.registerVirtualFileSystem(fs, makeDefault: true);

    final db = sqlite.open('/db.sqlite');
    db.execute('CREATE TABLE t (a TEXT)');
    db.execute("INSERT INTO t VALUES ('from the main database')");

    db.execute("ATTACH DATABASE '/artifact.db' AS artifact");
    db.execute('BEGIN');
    db.execute('CREATE TABLE artifact.rows (a TEXT)');
    db.execute('INSERT INTO artifact.rows SELECT a FROM t');
    db.execute('COMMIT');
    db.execute('DETACH DATABASE artifact');
    db.dispose();

    final opened =
        fs.xOpen(Sqlite3Filename('/artifact.db'), SqlFlag.SQLITE_OPEN_READONLY);
    final size = opened.file.xFileSize();
    final bytes = Uint8List(size);
    opened.file.xRead(bytes, 0);
    opened.file.xClose();

    expect(size, greaterThan(0));
    expect(String.fromCharCodes(bytes.sublist(0, 15)), 'SQLite format 3');

    // And the attached database really held the copied row.
    final reopened = sqlite.open('/artifact.db');
    expect(reopened.select('SELECT a FROM rows').single['a'],
        'from the main database');
    reopened.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
