@TestOn('browser')
library;

import 'package:ardrive/drive_state_sqlite/artifact_sink.dart';
import 'package:ardrive/models/database/web_artifact_vfs.dart';
import 'package:sqlite3/wasm.dart';
import 'package:test/test.dart';

/// A received artifact is attached, read once and thrown away, so it is kept
/// out of IndexedDB. Persisting it cost about 14 s at 41,767 files in a
/// release build, block by block, for a file deleted moments later.
void main() {
  test('a received artifact can be attached and never reaches IndexedDB',
      () async {
    final sqlite3 = await WasmSqlite3.loadFromUrl(
      Uri.parse('http://127.0.0.1:8099/sqlite3.wasm'),
    );
    final dbName = 'received_artifact_${DateTime.now().microsecondsSinceEpoch}';
    final fs = await IndexedDbFileSystem.open(dbName: dbName);
    sqlite3.registerVirtualFileSystem(fs, makeDefault: true);
    webSqlite = (sqlite3: sqlite3, vfs: fs);
    addTearDown(() async {
      await fs.close();
      await IndexedDbFileSystem.deleteDatabase(dbName);
    });

    // An artifact as it arrives: the bytes of a SQLite database.
    final scratch = InMemoryFileSystem(name: 'received-artifact-scratch');
    sqlite3.registerVirtualFileSystem(scratch);
    final built = sqlite3.open('/artifact.db', vfs: scratch.name);
    built.execute('CREATE TABLE t (x TEXT)');
    built.execute("INSERT INTO t VALUES ('carried')");
    built.dispose();
    final bytes = scratch.fileData['/artifact.db']!;

    final source = await createArtifactSource('probe', bytes);
    final db = sqlite3.open('/main.db');
    db.execute('ATTACH DATABASE ? AS artifact', [source.path]);
    expect(db.select('SELECT x FROM artifact.t').single['x'], 'carried');

    // What a fresh page load would find: only what reached IndexedDB.
    await fs.flush();
    final reloaded = await IndexedDbFileSystem.open(dbName: dbName);
    expect(reloaded.xAccess(source.path, 0), 0,
        reason: 'the received artifact was written to IndexedDB');
    await reloaded.close();

    db.execute('DETACH DATABASE artifact');
    await source.dispose();
    db.dispose();

    expect(fs.xAccess(source.path, 0), 0, reason: 'disposed, so gone');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
