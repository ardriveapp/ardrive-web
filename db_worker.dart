// The web database, in a dedicated worker, on OPFS.
//
// Compiled to db_worker.js with `dart compile js -O4` and served beside
// sqlite3.wasm. See docs/WEB_DATABASE.md.
//
// The page talks to the database through drift's remote protocol, on the port
// it hands over in `serve`, and to this worker through short requests, each
// carrying its own reply port:
//
//   open      {name, mode: writer|reader, sqlite3Url, seed?}
//   migrate   {bytes?}            writer only, before serve
//   serve     {port}
//   putFile   {path, bytes}       in-memory paths only: drive state artifacts
//   readFile  {path}
//   deleteFile{path}
import 'dart:async';
import 'dart:html';
import 'dart:js_util' as js_util;
import 'dart:typed_data';

import 'package:ardrive/models/database/web_worker/port_channel.dart';
import 'package:drift/drift.dart';
import 'package:drift/remote.dart';
import 'package:drift/wasm.dart';
import 'package:sqlite3/wasm.dart';

const _databasePath = '/database';
const _root = 'ardrive-db';
const _migratedMarker = 'migrated';

WasmSqlite3? _sqlite3;
VirtualFileSystem? _fs;
String? _name;

void main() {
  DedicatedWorkerGlobalScope.instance.onMessage.listen((event) async {
    final msg = event.data as Map;
    final reply = msg['reply'] as MessagePort;
    try {
      reply.postMessage(await _handle(msg));
    } catch (e) {
      reply.postMessage({'ok': false, 'reason': 'error', 'error': '$e'});
    }
  });
}

Future<Map<String, Object?>> _handle(Map msg) async {
  switch (msg['kind']) {
    case 'open':
      return _open(msg);
    case 'migrate':
      return _migrate(msg['bytes'] as Uint8List?);
    case 'serve':
      final server = DriftServer(
        DatabaseConnection(
          WasmDatabase(sqlite3: _sqlite3!, path: _databasePath),
        ),
        allowRemoteShutdown: true,
      );
      server.serve((msg['port'] as MessagePort).channel());
      return {'ok': true};
    case 'putFile':
      final path = _ownPath(msg['path']);
      final file = _fs!
          .xOpen(Sqlite3Filename(path),
              SqlFlag.SQLITE_OPEN_CREATE | SqlFlag.SQLITE_OPEN_READWRITE)
          .file;
      try {
        final bytes = msg['bytes'] as Uint8List;
        file.xTruncate(0);
        file.xWrite(bytes, 0);
      } finally {
        file.xClose();
      }
      return {'ok': true};
    case 'readFile':
      final path = _ownPath(msg['path']);
      if (_fs!.xAccess(path, 0) == 0) return {'ok': false, 'reason': 'missing'};
      final file =
          _fs!.xOpen(Sqlite3Filename(path), SqlFlag.SQLITE_OPEN_READONLY).file;
      try {
        final bytes = Uint8List(file.xFileSize());
        file.xRead(bytes, 0);
        return {'ok': true, 'bytes': bytes};
      } finally {
        file.xClose();
      }
    case 'deleteFile':
      final path = _ownPath(msg['path']);
      if (_fs!.xAccess(path, 0) != 0) _fs!.xDelete(path, 0);
      return {'ok': true};
  }
  return {'ok': false, 'reason': 'error', 'error': 'unknown request'};
}

/// The file requests reach only in-memory files, never the database or its
/// journal, which only SQLite writes.
String _ownPath(Object? path) {
  final p = path as String;
  if (p == _databasePath || p.startsWith('$_databasePath-')) {
    throw StateError('$p is the database, not a file this worker hands out');
  }
  return p;
}

Future<Map<String, Object?>> _open(Map msg) async {
  _name = msg['name'] as String;
  // Loaded once: a writer retries its open while a departed worker's files
  // are released, and each retry would otherwise fetch the module again.
  final sqlite3 = _sqlite3 ??=
      await WasmSqlite3.loadFromUrl(Uri.parse(msg['sqlite3Url'] as String));

  if (msg['mode'] == 'reader') {
    // A copy of what another tab holds, in memory, gone when this tab closes.
    final seed = msg['seed'] as Uint8List?;
    if (seed != null && !_soundDatabase(sqlite3, seed, full: true)) {
      return {'ok': false, 'reason': 'corrupt'};
    }
    final memory = InMemoryFileSystem(name: 'ardrive-session');
    if (seed != null) memory.fileData[_databasePath] = seed;
    sqlite3.registerVirtualFileSystem(memory, makeDefault: true);
    _fs = memory;
    return {'ok': true};
  }

  final directory = await _opfsDirectory();
  if (directory == null) {
    return {'ok': false, 'reason': 'unsupported', 'hadData': false};
  }
  final hadData = await _hasFile(directory, _migratedMarker);
  final SimpleOpfsFileSystem fs;
  try {
    fs = await SimpleOpfsFileSystem.loadFromStorage('$_root/$_name');
  } catch (e) {
    final busy = '$e'.contains('NoModificationAllowed');
    return {
      'ok': false,
      'reason': busy ? 'busy' : 'error',
      'error': '$e',
      'hadData': hadData,
    };
  }
  sqlite3.registerVirtualFileSystem(fs, makeDefault: true);
  _fs = fs;
  return {'ok': true, 'needsMigration': !hadData};
}

/// Writes [bytes] as the database, before SQLite has opened it, then marks
/// the migration done. Nothing is marked until the bytes are flushed, so a
/// tab closed half way leaves an unmarked database and the next start writes
/// it again from the old store, which is never touched.
Future<Map<String, Object?>> _migrate(Uint8List? bytes) async {
  final fs = _fs!;
  var migrated = false;
  if (bytes != null && _soundDatabase(_sqlite3!, bytes, full: false)) {
    final file = fs
        .xOpen(Sqlite3Filename(_databasePath),
            SqlFlag.SQLITE_OPEN_CREATE | SqlFlag.SQLITE_OPEN_READWRITE)
        .file;
    try {
      file.xTruncate(0);
      file.xWrite(bytes, 0);
      file.xSync(0);
    } finally {
      file.xClose();
    }
    migrated = true;
  }
  final directory = await _opfsDirectory();
  await js_util.promiseToFuture<Object?>(
      js_util.callMethod(directory!, 'getFileHandle', [
    _migratedMarker,
    js_util.jsify({'create': true})
  ]));
  return {
    'ok': true,
    'migrated': migrated,
    'rejected': bytes != null && !migrated,
  };
}

/// Whether [bytes] are a SQLite database that holds together.
bool _soundDatabase(WasmSqlite3 sqlite3, Uint8List bytes,
    {required bool full}) {
  const header = 'SQLite format 3\u0000';
  if (bytes.length < 16 ||
      String.fromCharCodes(bytes.sublist(0, 16)) != header) {
    return false;
  }
  final scratch = InMemoryFileSystem(name: 'ardrive-check');
  sqlite3.registerVirtualFileSystem(scratch);
  scratch.fileData['/check'] = bytes;
  try {
    final db = sqlite3.open('/check', vfs: scratch.name);
    try {
      final check =
          db.select(full ? 'PRAGMA integrity_check' : 'PRAGMA quick_check');
      return check.length == 1 && check.first.values.first == 'ok';
    } finally {
      db.dispose();
    }
  } catch (_) {
    return false;
  } finally {
    sqlite3.unregisterVirtualFileSystem(scratch);
  }
}

/// This database's OPFS directory, created if missing, or null where the
/// browser has no OPFS.
Future<Object?> _opfsDirectory() async {
  final navigator =
      js_util.getProperty<Object?>(js_util.globalThis, 'navigator');
  final storage = navigator == null
      ? null
      : js_util.getProperty<Object?>(navigator, 'storage');
  if (storage == null || !js_util.hasProperty(storage, 'getDirectory')) {
    return null;
  }
  try {
    Object directory = await js_util.promiseToFuture<Object>(
        js_util.callMethod(storage, 'getDirectory', []));
    for (final segment in [_root, _name!]) {
      directory = await js_util.promiseToFuture<Object>(
          js_util.callMethod(directory, 'getDirectoryHandle', [
        segment,
        js_util.jsify({'create': true})
      ]));
    }
    return directory;
  } catch (_) {
    return null;
  }
}

Future<bool> _hasFile(Object directory, String name) async {
  try {
    await js_util.promiseToFuture<Object?>(
        js_util.callMethod(directory, 'getFileHandle', [name]));
    return true;
  } catch (_) {
    return false;
  }
}
