// Prints platform facts the findings document quotes.
// ignore_for_file: avoid_print

@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:sqlite3/wasm.dart';
import 'package:test/test.dart';

import 'prototype_suite.dart';

/// The browser half, and the one D12 rests on.
///
/// Requires `sqlite3.wasm` to be served with CORS. `tool/drive_state_prototype.sh`
/// starts that server and runs this file; see
/// `docs/drive-state/ATTACH_VFS_PROTOTYPE.md` for why the copy vendored at
/// `web/sqlite3.wasm` cannot be used.
const wasmUrl = String.fromEnvironment(
  'SQLITE_WASM_URL',
  defaultValue: 'http://127.0.0.1:8099/sqlite3.wasm',
);

void main() {
  late WasmSqlite3 sqlite;
  late InMemoryFileSystem vfs;

  setUpAll(() async {
    sqlite = await WasmSqlite3.loadFromUrl(Uri.parse(wasmUrl));
    vfs = InMemoryFileSystem();
    sqlite.registerVirtualFileSystem(vfs, makeDefault: true);
  });

  runAttachPrototypeSuite(
    platform: 'web/wasm',
    open: (path) => sqlite.open(path),
    readBytes: (path) => Uint8List.fromList(vfs.fileData[path]!),
    writeBytes: (path, bytes) => vfs.fileData[path] = Uint8List.fromList(bytes),
    pathFor: (name) => '/$name',
    reset: () => vfs.fileData.clear(),
  );

  test('the VFS is what actually held the attached databases', () {
    vfs.fileData.clear();
    final source = sqlite.open('/source.db');
    createSourceDatabase(source, fileRows: 10);
    source.execute("ATTACH DATABASE '/second.db' AS artifact");
    source.execute('CREATE TABLE artifact.t (a TEXT)');
    source.execute("INSERT INTO artifact.t VALUES ('written through ATTACH')");
    source.execute('DETACH DATABASE artifact');
    source.dispose();

    // The attached database is a real, separate entry in the virtual
    // filesystem, not a fiction inside the first connection.
    expect(vfs.fileData.keys, contains('/second.db'));
    expect(vfs.fileData['/second.db']!.length, greaterThan(0));
    expect(
      String.fromCharCodes(vfs.fileData['/second.db']!.sublist(0, 15)),
      'SQLite format 3',
    );
  });

  test('reports the wasm library version this run proved things against', () {
    print('[web/wasm] sqlite ${sqlite.version.libVersion}');
    expect(sqlite.version.libVersion, isNotEmpty);
  });
}
