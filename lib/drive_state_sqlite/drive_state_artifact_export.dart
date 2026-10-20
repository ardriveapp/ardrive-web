/// Building a drive state artifact: `ATTACH`, `INSERT … SELECT`, `DETACH`.
///
/// No row becomes a Dart object at any point. That is the whole claim, and it
/// is why this file is short — the work happens inside SQLite, and what is
/// written here is only which columns move.
library;

import 'package:ardrive/drive_state_sqlite/artifact_attach_lock.dart';
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

  /// Some of the drive's own changes are still waiting to be confirmed on
  /// chain. See `unconfirmedMetadataCountSql`.
  unconfirmedChanges,

  /// The caller stopped wanting it, such as a snapshot modal that was
  /// cancelled. Checked between tables, so the export holds the database no
  /// longer than the table it is copying.
  cancelled,
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
/// stops a browser tab trying to build something it cannot hold. It can be
/// lower than the format's own bound but never usefully higher: every reader
/// refuses a payload over `DriveStateEnvelopeCodec`'s 100 MiB (D5), so an
/// artifact built past it would be paid for and unreadable.
Future<DriveStateArtifact> exportDriveState(
  GeneratedDatabase db, {
  required String driveId,
  required ArtifactSink sink,
  required int blockEnd,

  /// The client that built the artifact, as `<App-Name>/<App-Version>`.
  required String producer,
  int? maxBytes,

  /// Asked between tables. When it returns true the export stops, rolls back
  /// and is refused as [ArtifactExportRefusal.cancelled].
  bool Function()? isCancelled,
}) async {
  final drive = await db.customSelect(
    'SELECT ownerAddress, privacy FROM drives WHERE id = ?',
    variables: [Variable<String>(driveId)],
  ).get();
  if (drive.isEmpty) {
    throw ArtifactExportRefused(ArtifactExportRefusal.noSuchDrive, driveId);
  }

  void stopIfCancelled() {
    if (isCancelled?.call() ?? false) {
      throw ArtifactExportRefused(ArtifactExportRefusal.cancelled, driveId);
    }
  }

  try {
    return await artifactAttachLock.synchronized(() async {
      // Waiting for the lock can take as long as another export.
      stopIfCancelled();
      await detachLeftoverArtifact(db);
      await db.customStatement('ATTACH DATABASE ? AS artifact', [sink.path]);

      final int entityCount;
      try {
        await db.customStatement(
          'PRAGMA artifact.application_id = $artifactApplicationId',
        );
        // One database snapshot for the whole export. Without it a local sync
        // write can commit between the entry copy and the revision copy, and
        // the artifact then carries mismatched state that passes both the
        // schema gate and the entity count — an artifact whose files are
        // hidden after import because their revisions describe a different
        // moment.
        //
        // Drift's transaction, never a raw `BEGIN`. The connection is shared
        // with sync: a raw transaction let a sync batch's own `BEGIN` fail
        // inside it, and let a refusal's `ROLLBACK` discard sync writes that
        // landed in it. Drift's makes everything else wait until it ends.
        //
        // Opened after ATTACH because SQLite refuses to attach inside a
        // transaction.
        entityCount = await db.transaction(() async {
          for (final ddl in artifactSchema.entries) {
            await db.customStatement(
              ddl.value.replaceFirst('CREATE TABLE ', 'CREATE TABLE artifact.'),
            );
          }

          for (final entry in artifactProjection.entries) {
            stopIfCancelled();
            final table = entry.key;
            final columns = entry.value.join(', ');
            // Aliased `t` so the chain-only predicate can name its own row.
            final qualified = entry.value.map((c) => 't.$c').join(', ');
            final chainOnly = artifactChainOnlyPredicate[table];
            await db.customStatement(
              'INSERT INTO artifact.$table ($columns) '
              'SELECT $qualified FROM main.$table t '
              'WHERE t.${driveFilterColumn(table)} = ?'
              '${chainOnly == null ? '' : ' AND $chainOnly'}',
              [driveId],
            );
          }

          final unconfirmed =
              (await db.customSelect(unconfirmedMetadataCountSql).getSingle())
                  .read<int>('c');
          if (unconfirmed > 0) {
            throw ArtifactExportRefused(
              ArtifactExportRefusal.unconfirmedChanges,
              '$unconfirmed recent ${unconfirmed == 1 ? 'change' : 'changes'} '
              'to this drive ${unconfirmed == 1 ? 'is' : 'are'} still being '
              'confirmed on Arweave. Try again in a few minutes.',
            );
          }
          await db.customStatement(unconfirmedTransactionsSql());

          // Entities, not rows: a revision is a version of an entity, not
          // another one. Folders and files plus the drive itself, matching the
          // `Entity-Count` tag the proposal specifies.
          final counted = await db
              .customSelect(
                'SELECT ('
                '(SELECT count(*) FROM artifact.folder_entries) + '
                '(SELECT count(*) FROM artifact.file_entries) + '
                '(SELECT count(*) FROM artifact.drives)) AS c',
              )
              .getSingle();
          final count = counted.read<int>('c');
          if (count == 0) {
            throw ArtifactExportRefused(
                ArtifactExportRefusal.emptyDrive, driveId);
          }

          await db.customStatement(
            'INSERT INTO artifact.meta '
            '(version, driveId, ownerAddress, privacy, blockStart, blockEnd, '
            'entityCount, producer) VALUES (?, ?, ?, ?, 0, ?, ?, ?)',
            [
              artifactFormatVersion,
              driveId,
              drive.single.read<String>('ownerAddress'),
              drive.single.read<String>('privacy'),
              blockEnd,
              count,
              producer,
            ],
          );
          return count;
        });
      } catch (_) {
        // The transaction has rolled back. A failure here must not mask the
        // original error, and the lock's next holder detaches a leftover.
        try {
          await db.customStatement('DETACH DATABASE artifact');
        } catch (_) {}
        rethrow;
      }

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
    });
  } finally {
    await sink.dispose();
  }
}
