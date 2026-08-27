/// Reading a drive state artifact: validate everything, then merge in one
/// transaction.
///
/// The order is the point. Nothing is written until the file has proved it is
/// a well-formed database, carrying exactly the schema this reader agreed to,
/// making claims that match what was asked for. Only then does a single
/// transaction copy rows across — and, as in the exporter, no row becomes a
/// Dart object on the way.
library;

import 'package:ardrive/drive_state_sqlite/drive_state_artifact_schema.dart';
import 'package:drift/drift.dart';

/// Why an artifact was not used.
///
/// **Every one of these is a fallback, not an error.** No drive may fail
/// because an artifact was bad; the caller logs the reason and syncs the
/// ordinary way. Enumerating them is what lets that log answer *why* a drive
/// did not use its artifact — the failure this whole line of work came from
/// was a silent fallback nobody could diagnose.
enum ArtifactImportRefusal {
  /// `PRAGMA integrity_check` did not return `ok`. A gateway served a body
  /// that arrived wrong, or the file was never a database.
  notADatabase,

  /// The file carries something other than the frozen schema — a view, a
  /// trigger, a virtual table, an extra table, or a table whose DDL differs.
  /// This is the check that keeps an untrusted file from exercising more of
  /// SQLite than reading rows.
  unexpectedSchema,

  /// `meta` is missing, empty, or holds more than one row.
  malformedMeta,

  /// A major version this reader does not implement, in either direction.
  unsupportedVersion,

  /// The artifact describes a different drive than the one being synced.
  driveIdMismatch,

  /// The owner in the payload is not the owner this client knows. The payload
  /// is what the owner signed; the tags are chosen by whoever posted the
  /// transaction.
  ownerMismatch,

  /// The privacy in the payload contradicts the drive being synced.
  privacyMismatch,

  /// `meta.entityCount` disagrees with what the body actually holds. Cheap,
  /// and decisive: it proves the body meant what its own header promised.
  entityCountMismatch,

  /// The artifact covers no more than what is already synced. A no-op, never a
  /// regression.
  rangeAlreadyCovered,
}

class ArtifactImportRefused implements Exception {
  final ArtifactImportRefusal reason;
  final String detail;
  ArtifactImportRefused(this.reason, this.detail);
  @override
  String toString() => 'ArtifactImportRefused($reason): $detail';
}

/// Where a received artifact is placed so SQLite can open it. The mirror of
/// `ArtifactSink`.
abstract class ArtifactSource {
  String get path;
  Future<void> dispose();
}

class ArtifactImportResult {
  final int entityCount;
  final int blockEnd;
  final Map<String, int> rowsByTable;
  final int transactionsRegenerated;

  const ArtifactImportResult({
    required this.entityCount,
    required this.blockEnd,
    required this.rowsByTable,
    required this.transactionsRegenerated,
  });

  int get totalRows => rowsByTable.values.fold(0, (a, b) => a + b);
}

/// Merges the artifact at [source] into [db].
///
/// [knownOwner] and [knownPrivacy] are what this client already believes about
/// the drive. They are checked against the payload rather than the tags,
/// because the payload is the half somebody signed.
///
/// [syncedToBlock] is this client's current watermark; an artifact that covers
/// no more than it is refused rather than applied.
Future<ArtifactImportResult> importDriveState(
  GeneratedDatabase db, {
  required String driveId,
  required ArtifactSource source,
  required String knownOwner,
  required String knownPrivacy,
  required int syncedToBlock,
}) async {
  try {
    await db.customStatement('ATTACH DATABASE ? AS artifact', [source.path]);
    try {
      await _validate(
        db,
        driveId: driveId,
        knownOwner: knownOwner,
        knownPrivacy: knownPrivacy,
        syncedToBlock: syncedToBlock,
      );

      final meta = await db
          .customSelect('SELECT * FROM artifact.meta')
          .getSingle();

      return await db.transaction(() async {
        final rows = <String, int>{};
        for (final entry in artifactProjection.entries) {
          final columns = entry.value.join(', ');
          await db.customStatement(
            'INSERT OR REPLACE INTO main.${entry.key} ($columns) '
            'SELECT $columns FROM artifact.${entry.key}',
          );
          rows[entry.key] = await _count(db, 'artifact.${entry.key}');
        }

        var before = await _count(db, 'main.network_transactions');
        for (final sql in regenerateNetworkTransactionsSql('artifact')) {
          await db.customStatement(sql);
        }
        final after = await _count(db, 'main.network_transactions');

        return ArtifactImportResult(
          entityCount: meta.read<int>('entityCount'),
          blockEnd: meta.read<int>('blockEnd'),
          rowsByTable: rows,
          transactionsRegenerated: after - before,
        );
      });
    } finally {
      await db.customStatement('DETACH DATABASE artifact');
    }
  } finally {
    await source.dispose();
  }
}

/// The part of validation that is about the *file* rather than about the drive
/// it claims to describe: it is a well-formed database, and it is only the
/// shape this reader agreed to.
///
/// Exposed separately because the importer in `lib/drive_state/` runs it
/// before reading a single row, while its own guards — identity, coverage,
/// version — are already implemented there and operate on the parsed rows.
/// One gate, one place, called from both.
///
/// Returns null when the file is acceptable.
Future<ArtifactImportRefused?> validateAttachedArtifact(
  GeneratedDatabase db, {
  required String alias,
}) async {
  final integrity =
      await db.customSelect('PRAGMA $alias.integrity_check').getSingle();
  final verdict = integrity.data.values.first;
  if (verdict != 'ok') {
    return ArtifactImportRefused(
      ArtifactImportRefusal.notADatabase,
      '$verdict',
    );
  }

  // A view or trigger here would run this reader's own SELECT against
  // attacker-chosen SQL, so the shape is settled before any row is read.
  final objects = await db.customSelect(
    'SELECT type, name, sql FROM $alias.sqlite_master '
    "WHERE name NOT LIKE 'sqlite_%'",
  ).get();
  final seen = <String, String>{};
  for (final row in objects) {
    final type = row.read<String>('type');
    final name = row.read<String>('name');
    if (type != 'table') {
      return ArtifactImportRefused(
        ArtifactImportRefusal.unexpectedSchema,
        'found $type "$name"',
      );
    }
    seen[name] = row.read<String>('sql');
  }
  if (seen.length != artifactSchema.length) {
    return ArtifactImportRefused(
      ArtifactImportRefusal.unexpectedSchema,
      'expected ${artifactSchema.keys.toList()}, found ${seen.keys.toList()}',
    );
  }
  for (final entry in artifactSchema.entries) {
    if (seen[entry.key] != entry.value) {
      return ArtifactImportRefused(
        ArtifactImportRefusal.unexpectedSchema,
        'table "${entry.key}" is not the frozen schema',
      );
    }
  }
  return null;
}

Future<int> _count(GeneratedDatabase db, String table) async =>
    (await db.customSelect('SELECT count(*) AS c FROM $table').getSingle())
        .read<int>('c');

Future<void> _validate(
  GeneratedDatabase db, {
  required String driveId,
  required String knownOwner,
  required String knownPrivacy,
  required int syncedToBlock,
}) async {
  final integrity =
      await db.customSelect('PRAGMA artifact.integrity_check').getSingle();
  if (integrity.data.values.first != 'ok') {
    throw ArtifactImportRefused(
      ArtifactImportRefusal.notADatabase,
      '${integrity.data.values.first}',
    );
  }

  // Nothing but the tables we froze. A view or trigger here would run our own
  // SELECT against attacker-chosen SQL, so the shape is checked before a
  // single row is read.
  final objects = await db.customSelect(
    'SELECT type, name, sql FROM artifact.sqlite_master '
    "WHERE name NOT LIKE 'sqlite_%'",
  ).get();
  final seen = <String, String>{};
  for (final row in objects) {
    final type = row.read<String>('type');
    final name = row.read<String>('name');
    if (type != 'table') {
      throw ArtifactImportRefused(
        ArtifactImportRefusal.unexpectedSchema,
        'found $type "$name"',
      );
    }
    seen[name] = row.read<String>('sql');
  }
  if (seen.length != artifactSchema.length) {
    throw ArtifactImportRefused(
      ArtifactImportRefusal.unexpectedSchema,
      'expected ${artifactSchema.keys.toList()}, found ${seen.keys.toList()}',
    );
  }
  for (final entry in artifactSchema.entries) {
    if (seen[entry.key] != entry.value) {
      throw ArtifactImportRefused(
        ArtifactImportRefusal.unexpectedSchema,
        'table "${entry.key}" is not the frozen schema',
      );
    }
  }

  final metaRows = await db.customSelect('SELECT * FROM artifact.meta').get();
  if (metaRows.length != 1) {
    throw ArtifactImportRefused(
      ArtifactImportRefusal.malformedMeta,
      '${metaRows.length} rows',
    );
  }
  final meta = metaRows.single;

  final version = meta.read<String>('version');
  if (!artifactVersionIsReadable(version)) {
    throw ArtifactImportRefused(
      ArtifactImportRefusal.unsupportedVersion,
      version,
    );
  }
  if (meta.read<String>('driveId') != driveId) {
    throw ArtifactImportRefused(
      ArtifactImportRefusal.driveIdMismatch,
      meta.read<String>('driveId'),
    );
  }
  if (meta.read<String>('ownerAddress') != knownOwner) {
    throw ArtifactImportRefused(
      ArtifactImportRefusal.ownerMismatch,
      meta.read<String>('ownerAddress'),
    );
  }
  if (meta.read<String>('privacy') != knownPrivacy) {
    throw ArtifactImportRefused(
      ArtifactImportRefusal.privacyMismatch,
      meta.read<String>('privacy'),
    );
  }

  final actual = (await db.customSelect(
    'SELECT ('
    '(SELECT count(*) FROM artifact.folder_entries) + '
    '(SELECT count(*) FROM artifact.file_entries) + '
    '(SELECT count(*) FROM artifact.drives)) AS c',
  ).getSingle())
      .read<int>('c');
  if (actual != meta.read<int>('entityCount')) {
    throw ArtifactImportRefused(
      ArtifactImportRefusal.entityCountMismatch,
      'meta says ${meta.read<int>('entityCount')}, body has $actual',
    );
  }

  if (meta.read<int>('blockEnd') <= syncedToBlock) {
    throw ArtifactImportRefused(
      ArtifactImportRefusal.rangeAlreadyCovered,
      'artifact ends at ${meta.read<int>('blockEnd')}, '
      'already synced to $syncedToBlock',
    );
  }
}
