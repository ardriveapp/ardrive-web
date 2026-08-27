/// Reading and editing a drive state artifact with SQL.
///
/// The artifact is a SQLite database, so a fixture that needs one field to
/// disagree with its tags writes that field with a statement rather than
/// reaching into a decoded map.
///
/// **Raw sqlite3, never Drift.** Opening an artifact through `Database()`
/// runs its `onCreate` and writes the app's entire schema into the file,
/// which the reader's schema gate then refuses for a reason that has nothing
/// to do with the test.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart' as raw;

/// Runs [statements] against an artifact's bytes and hands back what they
/// leave behind.
Uint8List editArtifact(Uint8List bytes, List<String> statements) =>
    _withArtifact(bytes, (db, path) {
      for (final statement in statements) {
        db.execute(statement);
      }
      return null;
    }).bytes;

/// One row out of an artifact, for the tests that have to name a value the
/// payload actually carries.
Map<String, Object?> artifactRow(Uint8List bytes, String sql) =>
    _withArtifact(bytes, (db, path) {
      return Map<String, Object?>.from(db.select(sql).first);
    }).value!;

/// The first column of the first row [sql] returns.
Object? artifactValue(Uint8List bytes, String sql) =>
    artifactRow(bytes, sql).values.first;

/// The `Entity-Count` a correct producer tags an artifact with: its folders,
/// its files, and the drive itself, counted out of the container rather than
/// restated beside it.
int entitiesIn(Uint8List bytes) => artifactValue(
      bytes,
      'SELECT (SELECT count(*) FROM drives) '
      '+ (SELECT count(*) FROM folder_entries) '
      '+ (SELECT count(*) FROM file_entries) AS c',
    )! as int;

/// Drift stores `DATETIME` as unix seconds and the artifact carries the
/// column through unchanged, so a date read out of one is seconds.
DateTime artifactDate(Object? seconds) =>
    DateTime.fromMillisecondsSinceEpoch((seconds! as int) * 1000);

({Uint8List bytes, Map<String, Object?>? value}) _withArtifact(
  Uint8List bytes,
  Map<String, Object?>? Function(raw.Database db, String path) work,
) {
  final dir = Directory.systemTemp.createTempSync('drive-state-artifact');
  try {
    final path = '${dir.path}/artifact.db';
    File(path).writeAsBytesSync(bytes);
    final db = raw.sqlite3.open(path);
    final Map<String, Object?>? value;
    try {
      value = work(db, path);
    } finally {
      db.dispose();
    }
    return (bytes: File(path).readAsBytesSync(), value: value);
  } finally {
    dir.deleteSync(recursive: true);
  }
}
