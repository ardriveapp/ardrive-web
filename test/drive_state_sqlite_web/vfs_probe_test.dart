@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:sqlite3/wasm.dart';
import 'package:test/test.dart';

/// How does an artifact's bytes come back out of a VFS on web?
///
/// `IndexedDbFileSystem` keeps its file map private, so the direct read that
/// works for `InMemoryFileSystem` is unavailable — and URI filenames turn out
/// to be disabled in this build, so `ATTACH ... 'file:/x?vfs=other'` is taken
/// as a literal filename (asserted below, so the finding does not have to be
/// rediscovered).
///
/// What does work is the VFS interface itself: `xOpen` and `xRead` are public
/// on every `VirtualFileSystem`. So the artifact can be attached as an
/// ordinary file on whichever VFS the app already uses, and read back through
/// the same interface SQLite reads it through.
void main() {
  test('a ?vfs= URI is NOT honoured — filenames are literal in this build',
      () async {
    final sqlite = await WasmSqlite3.loadFromUrl(
      Uri.parse('http://127.0.0.1:8099/sqlite3.wasm'),
    );
    final main = InMemoryFileSystem(name: 'main-vfs');
    final other = InMemoryFileSystem(name: 'other-vfs');
    sqlite.registerVirtualFileSystem(main, makeDefault: true);
    sqlite.registerVirtualFileSystem(other);

    final db = sqlite.open('/db.sqlite');
    db.execute("ATTACH DATABASE 'file:/a.db?vfs=other-vfs' AS a");
    db.execute('CREATE TABLE a.t (x TEXT)');
    db.execute('DETACH DATABASE a');
    db.dispose();

    expect(other.fileData, isEmpty,
        reason: 'if this ever passes, URI filenames were enabled and the '
            'artifact can be steered to its own VFS');
    expect(main.fileData.keys, contains('/file:/a.db?vfs=other-vfs'));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('xOpen/xRead reads an attached artifact back out of any VFS', () async {
    final sqlite = await WasmSqlite3.loadFromUrl(
      Uri.parse('http://127.0.0.1:8099/sqlite3.wasm'),
    );

    // Deliberately the VFS whose file map is private, because that is the one
    // the app will actually be using.
    final vfs = InMemoryFileSystem(name: 'app-vfs');
    sqlite.registerVirtualFileSystem(vfs, makeDefault: true);

    final db = sqlite.open('/db.sqlite');
    db.execute('CREATE TABLE t (a TEXT)');
    db.execute("INSERT INTO t VALUES ('main db row')");

    db.execute("ATTACH DATABASE '/artifact.db' AS artifact");
    db.execute('CREATE TABLE artifact.rows (a TEXT)');
    db.execute('INSERT INTO artifact.rows SELECT a FROM t');
    db.execute('DETACH DATABASE artifact');
    db.dispose();

    // Read it back the way SQLite would: through the VFS interface, which is
    // public on every implementation.
    final opened = vfs.xOpen(Sqlite3Filename('/artifact.db'), 0);
    final size = opened.file.xFileSize();
    final bytes = Uint8List(size);
    opened.file.xRead(bytes, 0);
    opened.file.xClose();

    expect(size, greaterThan(4096));
    expect(String.fromCharCodes(bytes.sublist(0, 15)), 'SQLite format 3');

    // And it can be cleaned up through the same interface.
    vfs.xDelete('/artifact.db', 0);
    expect(vfs.xAccess('/artifact.db', 0), 0);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
