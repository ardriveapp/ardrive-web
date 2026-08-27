/// The browser.
///
/// An artifact is attached as an ordinary file on the same virtual filesystem
/// the app's database already uses, and read back through the VFS interface —
/// `xOpen`, `xFileSize`, `xRead`, `xDelete` — which is public on every
/// implementation.
///
/// That last part is the whole reason web works. `IndexedDbFileSystem` keeps
/// its file map private, so the direct read that works for
/// `InMemoryFileSystem` is unavailable, and URI filenames are disabled in this
/// build so an artifact cannot be steered onto a VFS of its own. Reading it
/// the way SQLite reads it sidesteps both. Proven in
/// `test/drive_state_sqlite_web/vfs_probe_test.dart`.
library;

import 'dart:typed_data';

import 'package:ardrive/drive_state_sqlite/artifact_sink.dart';
import 'package:ardrive/drive_state_sqlite/drive_state_artifact_export.dart';
import 'package:ardrive/drive_state_sqlite/drive_state_artifact_import.dart';
import 'package:ardrive/models/database/web_artifact_vfs.dart';
import 'package:sqlite3/wasm.dart';

/// False until the database has been opened, because the sqlite3 instance an
/// artifact must be attached to is the one the database created. Callers check
/// this before offering to publish, so a user is told the platform is not
/// ready rather than shown a failure.
bool get artifactSinkSupported => webSqlite != null;

VirtualFileSystem get _vfs {
  final held = webSqlite;
  if (held == null) {
    throw ArtifactSinkUnsupported('the web database has not been opened yet');
  }
  return held.vfs;
}

/// Artifacts live beside the database on the same filesystem. Named per drive
/// so two exports cannot collide, and deleted on dispose either way — an
/// artifact left behind would be persisted to IndexedDB along with everything
/// else on this filesystem.
String _pathFor(String label) => '/drive_state_$label.db';

Future<ArtifactSink> createArtifactSink(String label) async {
  final path = _pathFor(label);
  final vfs = _vfs;
  // A leftover from an interrupted run would otherwise be attached and
  // appended to, producing an artifact with two drives' rows in it.
  if (vfs.xAccess(path, 0) != 0) vfs.xDelete(path, 0);
  return _VfsSink(path, vfs);
}

Future<ArtifactSource> createArtifactSource(
  String label,
  List<int> bytes,
) async {
  final path = _pathFor('received_$label');
  final vfs = _vfs;
  if (vfs.xAccess(path, 0) != 0) vfs.xDelete(path, 0);

  final file = vfs
      .xOpen(
        Sqlite3Filename(path),
        SqlFlag.SQLITE_OPEN_CREATE | SqlFlag.SQLITE_OPEN_READWRITE,
      )
      .file;
  try {
    file.xWrite(Uint8List.fromList(bytes), 0);
  } finally {
    file.xClose();
  }
  return _VfsSource(path, vfs);
}

class _VfsSink implements ArtifactSink {
  @override
  final String path;
  final VirtualFileSystem _fs;
  _VfsSink(this.path, this._fs);

  @override
  Future<Uint8List> read() async {
    final file = _fs.xOpen(Sqlite3Filename(path), SqlFlag.SQLITE_OPEN_READONLY)
        .file;
    try {
      final bytes = Uint8List(file.xFileSize());
      file.xRead(bytes, 0);
      return bytes;
    } finally {
      file.xClose();
    }
  }

  @override
  Future<void> dispose() async {
    if (_fs.xAccess(path, 0) != 0) _fs.xDelete(path, 0);
  }
}

class _VfsSource implements ArtifactSource {
  @override
  final String path;
  final VirtualFileSystem _fs;
  _VfsSource(this.path, this._fs);

  @override
  Future<void> dispose() async {
    if (_fs.xAccess(path, 0) != 0) _fs.xDelete(path, 0);
  }
}
