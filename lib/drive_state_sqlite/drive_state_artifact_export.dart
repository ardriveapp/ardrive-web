/// Building a drive state artifact: `ATTACH`, `INSERT … SELECT`, `DETACH`.
///
/// No row becomes a Dart object at any point. That is the whole claim, and it
/// is why this file is short — the work happens inside SQLite, and what is
/// written here is only which columns move.
library;


import 'package:ardrive/drive_state_sqlite/drive_state_artifact_schema.dart';
import 'package:drift/drift.dart';

/// Why an artifact could not be produced.
///
/// Every one is a refusal with a reason, never a thrown surprise: the caller
/// tells the user why and nothing else changes.
enum ArtifactExportRefusal {
  /// No drive with this id, or it is not the caller's to publish.
  noSuchDrive,

  /// The drive holds nothing worth publishing.
  emptyDrive,

  /// The finished artifact is larger than the producer bound.
  tooLarge,
}

class ArtifactExportRefused implements Exception {
  final ArtifactExportRefusal reason;
  final String detail;
  ArtifactExportRefused(this.reason, this.detail);
  @override
  String toString() => 'ArtifactExportRefused($reason): $detail';
}

/// Where the exporter puts the artifact while it builds it, and how it reads
/// the bytes back.
///
/// A real file on the VM and in the CLI; a VFS entry in the browser. The
/// exporter does not care which, and that is deliberate — this is the seam
/// that lets the same code run in a Flutter tab and in a Node CLI producing an
/// artifact for a drive far too large for a browser.
abstract class ArtifactSink {
  /// The path SQLite should `ATTACH`.
  String get path;

  /// How large the artifact is, without materialising it.
  ///
  /// Separate from [read] so an oversized artifact can be refused before its
  /// bytes are pulled into memory — otherwise the bound meant to protect the
  /// producer's memory is only checked after that memory has been spent.
  Future<int> size();

  /// The bytes at [path], once the database has been detached.
  Future<Uint8List> read();

  /// Removes the working file. Called whether the export succeeded or not.
  Future<void> dispose();
}

class DriveStateArtifact {
  final Uint8List bytes;
  final int entityCount;
  final int blockEnd;
  final String driveId;

  const DriveStateArtifact({
    required this.bytes,
    required this.entityCount,
    required this.blockEnd,
    required this.driveId,
  });
}

/// Copies one drive out of [db] into a fresh artifact database at [sink].
///
/// [maxBytes] is a bound on the **producer**, not on any cipher: it is what
/// stops a browser tab trying to build something it cannot hold. A CLI can
/// pass a much larger value, or none, which is the point of the parameter
/// existing rather than being a constant.
Future<DriveStateArtifact> exportDriveState(
  GeneratedDatabase db, {
  required String driveId,
  required ArtifactSink sink,
  required int blockEnd,
  int? maxBytes,
}) async {
  final drive = await db
      .customSelect(
        'SELECT ownerAddress, privacy FROM drives WHERE id = ?',
        variables: [Variable<String>(driveId)],
      )
      .get();
  if (drive.isEmpty) {
    throw ArtifactExportRefused(ArtifactExportRefusal.noSuchDrive, driveId);
  }

  try {
    await db.customStatement('ATTACH DATABASE ? AS artifact', [sink.path]);
    try {
      // One database snapshot for the whole export. Without it a local sync
      // write can commit between the entry copy and the revision copy, and the
      // artifact then carries mismatched state that passes both the schema gate
      // and the entity count — an artifact whose files are hidden after import
      // because their revisions describe a different moment.
      //
      // BEGIN comes after ATTACH because SQLite refuses to attach inside a
      // transaction.
      await db.customStatement('BEGIN');
      for (final ddl in artifactSchema.entries) {
        await db.customStatement(
          ddl.value.replaceFirst('CREATE TABLE ', 'CREATE TABLE artifact.'),
        );
      }

      for (final entry in artifactProjection.entries) {
        final table = entry.key;
        final columns = entry.value.join(', ');
        await db.customStatement(
          'INSERT INTO artifact.$table ($columns) '
          'SELECT $columns FROM main.$table '
          'WHERE ${driveFilterColumn(table)} = ?',
          [driveId],
        );
      }

      // Entities, not rows: a revision is a version of an entity, not another
      // one. Folders and files plus the drive itself, matching the
      // `Entity-Count` tag the proposal specifies.
      final counted = await db.customSelect(
        'SELECT ('
        '(SELECT count(*) FROM artifact.folder_entries) + '
        '(SELECT count(*) FROM artifact.file_entries) + '
        '(SELECT count(*) FROM artifact.drives)) AS c',
      ).getSingle();
      final entityCount = counted.read<int>('c');
      if (entityCount == 0) {
        throw ArtifactExportRefused(ArtifactExportRefusal.emptyDrive, driveId);
      }

      await db.customStatement(
        'INSERT INTO artifact.meta '
        '(version, driveId, ownerAddress, privacy, blockStart, blockEnd, '
        'entityCount) VALUES (?, ?, ?, ?, 0, ?, ?)',
        [
          artifactFormatVersion,
          driveId,
          drive.single.read<String>('ownerAddress'),
          drive.single.read<String>('privacy'),
          blockEnd,
          entityCount,
        ],
      );

      await db.customStatement('COMMIT');

      await db.customStatement('DETACH DATABASE artifact');

      // Weighed before it is read. `read()` would pull the whole file into
      // memory, which is the cost this bound exists to avoid paying.
      if (maxBytes != null) {
        final size = await sink.size();
        if (size > maxBytes) {
          throw ArtifactExportRefused(
            ArtifactExportRefusal.tooLarge,
            '$size bytes exceeds $maxBytes',
          );
        }
      }

      final bytes = await sink.read();

      return DriveStateArtifact(
        bytes: bytes,
        entityCount: entityCount,
        blockEnd: blockEnd,
        driveId: driveId,
      );
    } catch (_) {
      // Both may already have run; a second attempt is harmless and a failure
      // here must not mask the original error.
      try {
        await db.customStatement('ROLLBACK');
      } catch (_) {}
      try {
        await db.customStatement('DETACH DATABASE artifact');
      } catch (_) {}
      rethrow;
    }
  } finally {
    await sink.dispose();
  }
}
