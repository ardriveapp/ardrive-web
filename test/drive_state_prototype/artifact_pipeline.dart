/// The D12 drive-state artifact pipeline, expressed once, in SQL.
///
/// This is a **prototype**, not production code. It exists to answer the two
/// questions `docs/drive-state/ATTACH_VFS_PROTOTYPE.md` poses, and it is
/// written against `package:sqlite3/common.dart` so that the identical
/// statements run on the Dart VM (FFI) and in a browser (WASM). If the SQL
/// below works on both, D12's producer and consumer are both O(1) in drive
/// size with no serialisation code of our own.
///
/// Nothing here touches Drift, the app database, or any app code.
library;

import 'dart:typed_data';

import 'package:sqlite3/common.dart';

/// Reads the bytes of [path] out of whatever filesystem the caller's SQLite
/// is using — a real file on the VM, a VFS entry in the browser.
typedef ByteReader = Uint8List Function(String path);

/// Places [bytes] at [path] in that same filesystem, so SQLite can `ATTACH`
/// them.
typedef ByteWriter = void Function(String path, Uint8List bytes);

/// The columns each artifact table carries, named explicitly and never `*`.
///
/// This map is the **projection**, and in D12 it is also the security
/// boundary: a column absent from here cannot reach the artifact, because the
/// artifact is built by selecting these names into an empty database. There is
/// no step that removes anything, so there is no step that can be forgotten.
///
/// `profiles` is deliberately absent. It is not filtered out — it is never
/// named, anywhere, at any point in the pipeline.
const artifactProjection = <String, List<String>>{
  'drives': [
    // Note what is *not* here: encryptedKey, keyEncryptionIv,
    // driveKeyGenerated, lastBlockHeight, syncCursor.
    'id',
    'name',
    'ownerAddress',
    'privacy',
    'rootFolderId',
  ],
  'file_revisions': [
    'fileId',
    'driveId',
    'name',
    'parentFolderId',
    'size',
    'lastModifiedDate',
    'dataContentType',
    'metadataTxId',
    'dataTxId',
    'dateCreated',
    'action',
    'isHidden',
  ],
};

/// The frozen artifact schema — D12's, not Drift's.
///
/// Deliberately not the app's schema: no indexes (dead weight that measured
/// 1.66x on the compressed size), no foreign keys, and ids left as they come.
/// A reader compares the artifact's `sqlite_master` against exactly this text,
/// so it is written once and read by both halves.
const artifactSchema = <String, String>{
  'meta': 'CREATE TABLE meta ('
      'version TEXT NOT NULL, '
      'driveId TEXT NOT NULL, '
      'blockEnd INTEGER NOT NULL, '
      'entityCount INTEGER NOT NULL)',
  'drives': 'CREATE TABLE drives ('
      'id TEXT NOT NULL, '
      'name TEXT, '
      'ownerAddress TEXT NOT NULL, '
      'privacy TEXT NOT NULL, '
      'rootFolderId TEXT NOT NULL)',
  'file_revisions': 'CREATE TABLE file_revisions ('
      'fileId TEXT NOT NULL, '
      'driveId TEXT NOT NULL, '
      'name TEXT NOT NULL, '
      'parentFolderId TEXT NOT NULL, '
      'size INTEGER NOT NULL, '
      'lastModifiedDate INTEGER NOT NULL, '
      'dataContentType TEXT, '
      'metadataTxId TEXT NOT NULL, '
      'dataTxId TEXT NOT NULL, '
      'dateCreated INTEGER NOT NULL, '
      'action TEXT NOT NULL, '
      'isHidden INTEGER NOT NULL)',
};

/// Case 1 — the producer.
///
/// Attaches an **empty** database at [artifactPath], builds the frozen schema
/// inside it, copies one drive's rows in through the explicit projection, and
/// detaches. Returns the artifact's bytes.
///
/// Memory is whatever SQLite's page cache decides; no row ever becomes a Dart
/// object. That is the whole claim being tested.
Uint8List buildArtifact(
  CommonDatabase source, {
  required String artifactPath,
  required String driveId,
  required String version,
  required int blockEnd,
  required ByteReader readBytes,
}) {
  source.execute('ATTACH DATABASE ? AS artifact', [artifactPath]);
  try {
    for (final ddl in artifactSchema.values) {
      source.execute(ddl.replaceFirst('CREATE TABLE ', 'CREATE TABLE artifact.'));
    }

    for (final entry in artifactProjection.entries) {
      final table = entry.key;
      final columns = entry.value.join(', ');
      final idColumn = table == 'drives' ? 'id' : 'driveId';
      source.execute(
        'INSERT INTO artifact.$table ($columns) '
        'SELECT $columns FROM main.$table WHERE $idColumn = ?',
        [driveId],
      );
    }

    final entityCount = source
        .select('SELECT count(*) AS c FROM artifact.file_revisions')
        .single['c'] as int;
    source.execute(
      'INSERT INTO artifact.meta (version, driveId, blockEnd, entityCount) '
      'VALUES (?, ?, ?, ?)',
      [version, driveId, blockEnd, entityCount],
    );
  } finally {
    source.execute('DETACH DATABASE artifact');
  }

  return readBytes(artifactPath);
}

/// Why a received artifact was refused. Every one is a fallback, never an
/// error — the caller syncs the ordinary way.
enum ArtifactRejection {
  integrityCheckFailed,
  unexpectedSchema,
  versionMismatch,
  driveIdMismatch,
  entityCountMismatch,
}

class ArtifactRejected implements Exception {
  final ArtifactRejection reason;
  final String detail;
  ArtifactRejected(this.reason, this.detail);
  @override
  String toString() => 'ArtifactRejected($reason): $detail';
}

/// Case 2 — the consumer.
///
/// Places [bytes] in the filesystem, attaches them, refuses the file unless it
/// is exactly the shape this reader agreed to, then merges one drive's rows
/// with `INSERT INTO main.x SELECT ... FROM artifact.x`.
///
/// Returns the number of `file_revisions` rows merged.
int importArtifact(
  CommonDatabase target,
  Uint8List bytes, {
  required String artifactPath,
  required String expectedVersion,
  required String expectedDriveId,
  required ByteWriter writeBytes,
}) {
  writeBytes(artifactPath, bytes);
  target.execute('ATTACH DATABASE ? AS artifact', [artifactPath]);
  try {
    // (1) The file is a well-formed database.
    final integrity =
        target.select('PRAGMA artifact.integrity_check').first.values.first;
    if (integrity != 'ok') {
      throw ArtifactRejected(
          ArtifactRejection.integrityCheckFailed, '$integrity');
    }

    // (2) It is *only* the shape we agreed to. This is §2.4's first argument
    //     made explicit: no views, no triggers, no virtual tables, no indexes,
    //     and every table's DDL byte-identical to the frozen schema.
    final objects = target.select(
      'SELECT type, name, sql FROM artifact.sqlite_master '
      "WHERE name NOT LIKE 'sqlite_%'",
    );
    final seen = <String, String>{};
    for (final row in objects) {
      if (row['type'] != 'table') {
        throw ArtifactRejected(ArtifactRejection.unexpectedSchema,
            'found ${row['type']} "${row['name']}"');
      }
      seen[row['name'] as String] = row['sql'] as String;
    }
    if (seen.length != artifactSchema.length) {
      throw ArtifactRejected(ArtifactRejection.unexpectedSchema,
          'expected ${artifactSchema.keys.toList()}, found ${seen.keys.toList()}');
    }
    for (final entry in artifactSchema.entries) {
      if (seen[entry.key] != entry.value) {
        throw ArtifactRejected(ArtifactRejection.unexpectedSchema,
            'table "${entry.key}" is not the frozen schema');
      }
    }

    // (3) The claims inside the file match what we asked for.
    final meta = target.select('SELECT * FROM artifact.meta').single;
    if (meta['version'] != expectedVersion) {
      throw ArtifactRejected(
          ArtifactRejection.versionMismatch, '${meta['version']}');
    }
    if (meta['driveId'] != expectedDriveId) {
      throw ArtifactRejected(
          ArtifactRejection.driveIdMismatch, '${meta['driveId']}');
    }
    final actual = target
        .select('SELECT count(*) AS c FROM artifact.file_revisions')
        .single['c'] as int;
    if (actual != meta['entityCount']) {
      throw ArtifactRejected(ArtifactRejection.entityCountMismatch,
          'tag says ${meta['entityCount']}, body has $actual');
    }

    // (4) The merge. No Dart object is created for any row.
    target.execute('BEGIN');
    try {
      for (final entry in artifactProjection.entries) {
        final columns = entry.value.join(', ');
        target.execute(
          'INSERT OR REPLACE INTO main.${entry.key} ($columns) '
          'SELECT $columns FROM artifact.${entry.key}',
        );
      }
      target.execute('COMMIT');
    } catch (_) {
      target.execute('ROLLBACK');
      rethrow;
    }
    return actual;
  } finally {
    target.execute('DETACH DATABASE artifact');
  }
}
