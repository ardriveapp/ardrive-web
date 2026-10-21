/// Reads an attached artifact for the merge in `drive_state_import.dart`, and
/// builds the statements that copy its bulk tables across.
///
/// **Why the bulk tables never become Dart objects.** Reading every row into
/// Dart and writing it back cost 5.4 s on a 41,767 file drive, against 0.13 s
/// for SQLite to copy the largest table itself. The merge's decisions do not
/// need those rows in Dart:
///
///  * the revision tables and `licenses` only ever add (`INSERT OR IGNORE`),
///    so there is nothing to decide per row;
///  * `network_transactions` is derived from them by a fixed rule;
///  * `file_entries` needs one comparison per row, `lastUpdated` against the
///    local row, which is a `NOT EXISTS` against the same primary key.
///
/// What does need Dart stays in Dart, at the size of a drive's folder tree
/// rather than its file count: the drive row, the folders (ghost stand-ins,
/// cycle detection, the stand-in-loses rule), and `transaction_statuses`.
///
/// **What the copy has to preserve.** Reading through Dart was also a check:
/// a value of the wrong type threw, and the artifact was refused. A file
/// declares its column types, but SQLite stores whatever it is given, so
/// [artifactTypeViolation] makes the same refusal before anything is copied.
library;

import 'package:ardrive/drive_state/data/drive_state_export.dart';
import 'package:ardrive/drive_state/domain/drive_state_format_version.dart';
import 'package:ardrive/drive_state_sqlite/drive_state_artifact_schema.dart';
import 'package:drift/drift.dart';

/// What a column must hold for the merge to copy it.
enum ArtifactValue {
  text,
  nullableText,
  integer,

  /// Unix seconds, within what a Dart `DateTime` can represent. Drift reads
  /// the column back into one, so a value outside that range would throw
  /// every time the row is read.
  time,
}

/// Every column the merge copies with SQL, and what it must hold.
///
/// Exactly the reads `readArtifactAsExport` made through Dart, so a value it
/// refused is refused here. Text columns are text, not a value SQLite would
/// convert: a correct producer copies them from columns that hold text.
const artifactCopiedColumns = <String, Map<String, ArtifactValue>>{
  'file_entries': {
    'id': ArtifactValue.text,
    'driveId': ArtifactValue.text,
    'name': ArtifactValue.text,
    'parentFolderId': ArtifactValue.text,
    'size': ArtifactValue.integer,
    'lastModifiedDate': ArtifactValue.time,
    'dataContentType': ArtifactValue.nullableText,
    'dataTxId': ArtifactValue.text,
    'licenseTxId': ArtifactValue.nullableText,
    'bundledIn': ArtifactValue.nullableText,
    'thumbnail': ArtifactValue.nullableText,
    'pinnedDataOwnerAddress': ArtifactValue.nullableText,
    'customJsonMetadata': ArtifactValue.nullableText,
    'customGQLTags': ArtifactValue.nullableText,
    'isHidden': ArtifactValue.integer,
    'dateCreated': ArtifactValue.time,
    'lastUpdated': ArtifactValue.time,
    'assignedNames': ArtifactValue.nullableText,
    'fallbackTxId': ArtifactValue.nullableText,
    'originalOwner': ArtifactValue.nullableText,
    'importSource': ArtifactValue.nullableText,
  },
  'drive_revisions': {
    'driveId': ArtifactValue.text,
    'rootFolderId': ArtifactValue.text,
    'ownerAddress': ArtifactValue.text,
    'name': ArtifactValue.text,
    'privacy': ArtifactValue.text,
    'metadataTxId': ArtifactValue.text,
    'dateCreated': ArtifactValue.time,
    'action': ArtifactValue.text,
    'bundledIn': ArtifactValue.nullableText,
    'customJsonMetadata': ArtifactValue.nullableText,
    'customGQLTags': ArtifactValue.nullableText,
    'isHidden': ArtifactValue.integer,
  },
  'folder_revisions': {
    'folderId': ArtifactValue.text,
    'driveId': ArtifactValue.text,
    'name': ArtifactValue.text,
    'parentFolderId': ArtifactValue.nullableText,
    'metadataTxId': ArtifactValue.text,
    'dateCreated': ArtifactValue.time,
    'action': ArtifactValue.text,
    'customJsonMetadata': ArtifactValue.nullableText,
    'customGQLTags': ArtifactValue.nullableText,
    'isHidden': ArtifactValue.integer,
  },
  'file_revisions': {
    'fileId': ArtifactValue.text,
    'driveId': ArtifactValue.text,
    'name': ArtifactValue.text,
    'parentFolderId': ArtifactValue.text,
    'size': ArtifactValue.integer,
    'lastModifiedDate': ArtifactValue.time,
    'dataContentType': ArtifactValue.nullableText,
    'metadataTxId': ArtifactValue.text,
    'dataTxId': ArtifactValue.text,
    'licenseTxId': ArtifactValue.nullableText,
    'thumbnail': ArtifactValue.nullableText,
    'bundledIn': ArtifactValue.nullableText,
    'dateCreated': ArtifactValue.time,
    'customJsonMetadata': ArtifactValue.nullableText,
    'customGQLTags': ArtifactValue.nullableText,
    'action': ArtifactValue.text,
    'pinnedDataOwnerAddress': ArtifactValue.nullableText,
    'isHidden': ArtifactValue.integer,
    'assignedNames': ArtifactValue.nullableText,
    'fallbackTxId': ArtifactValue.nullableText,
    'originalOwner': ArtifactValue.nullableText,
    'importSource': ArtifactValue.nullableText,
  },
  'licenses': {
    'fileId': ArtifactValue.text,
    'driveId': ArtifactValue.text,
    'dataTxId': ArtifactValue.text,
    'licenseTxType': ArtifactValue.text,
    'licenseTxId': ArtifactValue.text,
    'bundledIn': ArtifactValue.nullableText,
    'dateCreated': ArtifactValue.time,
    'licenseType': ArtifactValue.text,
    'customGQLTags': ArtifactValue.nullableText,
  },
};

/// The largest magnitude, in seconds, a Dart `DateTime` holds: 8.64e15 ms.
const _maxSeconds = 8640000000000;

String _holds(String column, ArtifactValue value) => switch (value) {
      ArtifactValue.text => "typeof($column) = 'text'",
      ArtifactValue.nullableText => "typeof($column) IN ('text', 'null')",
      ArtifactValue.integer => "typeof($column) = 'integer'",
      ArtifactValue.time => "(typeof($column) = 'integer' AND $column "
          'BETWEEN -$_maxSeconds AND $_maxSeconds)',
    };

/// The first column of [table] in the artifact at [alias] holding a value the
/// merge cannot copy, or null when every row is well typed.
Future<String?> artifactTypeViolation(
  GeneratedDatabase db, {
  required String alias,
  required String table,
}) async {
  final columns = artifactCopiedColumns[table]!;
  // One scan for the common case, a clean table. Only a table that fails it
  // is scanned again, column by column, to name what is wrong.
  final clean = await db
      .customSelect(
        'SELECT 1 FROM $alias.$table WHERE NOT ('
        '${columns.entries.map((e) => _holds(e.key, e.value)).join(' AND ')}'
        ') LIMIT 1',
      )
      .getSingleOrNull();
  if (clean == null) return null;
  for (final entry in columns.entries) {
    final bad = await db
        .customSelect(
          'SELECT typeof(${entry.key}) AS t FROM $alias.$table '
          'WHERE NOT ${_holds(entry.key, entry.value)} LIMIT 1',
        )
        .getSingleOrNull();
    if (bad != null) {
      return '$table.${entry.key} holds a ${bad.read<String>('t')} value '
          'where the format declares ${entry.value.name}';
    }
  }
  return null;
}

/// Everything the merge decides in Dart, read from an attached artifact.
class ArtifactForMerge {
  final ExportedDrive drive;
  final List<ExportedFolderEntry> folders;

  /// The folders a `folder_revisions` row vouches for.
  final Set<String> vouchedFolderIds;

  final int fileCount;

  /// The first `driveId` in any section that is not the drive's own, in the
  /// order the sections are listed in the format. Null when every row belongs
  /// to [drive].
  final String? foreignDriveId;

  final DriveStateCoverage coverage;
  final DriveStateFormatVersion version;

  /// `transaction_statuses`, checked against [importedTransactionStatus].
  final Map<String, String> unconfirmedTransactions;

  const ArtifactForMerge({
    required this.drive,
    required this.folders,
    required this.vouchedFolderIds,
    required this.fileCount,
    required this.foreignDriveId,
    required this.coverage,
    required this.version,
    required this.unconfirmedTransactions,
  });

  int get entityCount => folders.length + fileCount + 1;
}

DateTime _time(QueryRow row, String column) =>
    DateTime.fromMillisecondsSinceEpoch(row.read<int>(column) * 1000);

bool _bool(QueryRow row, String column) => row.read<int>(column) != 0;

/// Reads the artifact attached as [alias] for the merge.
///
/// Throws [DriveStateFormatException] or a read error when the artifact is
/// malformed; the caller turns either into a refusal before anything is
/// written. Assumes `validateAttachedArtifact` has already passed.
Future<ArtifactForMerge> readArtifactForMerge(
  GeneratedDatabase db, {
  required String alias,
}) async {
  Future<List<QueryRow>> all(String sql) => db.customSelect(sql).get().then(
        (rows) => rows.map((r) => QueryRow(r.data, db)).toList(),
      );

  for (final table in artifactCopiedColumns.keys) {
    final violation =
        await artifactTypeViolation(db, alias: alias, table: table);
    if (violation != null) {
      throw DriveStateFormatException(
        DriveStateFormatError.malformed,
        violation,
      );
    }
  }

  // `file_entries` is the one copied table written by upsert, and two rows
  // for one file would leave whichever came last. A producer copies from a
  // table keyed on the id, so it never writes two.
  final duplicate = await db
      .customSelect(
        'SELECT id FROM $alias.file_entries GROUP BY id HAVING count(*) > 1 '
        'LIMIT 1',
      )
      .getSingleOrNull();
  if (duplicate != null) {
    throw DriveStateFormatException(
      DriveStateFormatError.malformed,
      'file ${duplicate.read<String>('id')} is listed twice',
    );
  }

  final driveRow = (await all('SELECT * FROM $alias.drives')).single;
  final meta = (await all('SELECT * FROM $alias.meta')).single;
  final drive = ExportedDrive(
    id: driveRow.read<String>('id'),
    rootFolderId: driveRow.read<String>('rootFolderId'),
    ownerAddress: driveRow.read<String>('ownerAddress'),
    name: driveRow.read<String>('name'),
    privacy: driveRow.read<String>('privacy'),
    bundledIn: driveRow.readNullable<String>('bundledIn'),
    customJsonMetadata: driveRow.readNullable<String>('customJsonMetadata'),
    customGQLTags: driveRow.readNullable<String>('customGQLTags'),
    isHidden: _bool(driveRow, 'isHidden'),
    signatureType: driveRow.readNullable<String>('signatureType'),
    dateCreated: _time(driveRow, 'dateCreated'),
    lastUpdated: _time(driveRow, 'lastUpdated'),
  );

  final folders = [
    for (final r in await all('SELECT * FROM $alias.folder_entries'))
      ExportedFolderEntry(
        id: r.read<String>('id'),
        driveId: r.read<String>('driveId'),
        name: r.read<String>('name'),
        parentFolderId: r.readNullable<String>('parentFolderId'),
        path: '',
        dateCreated: _time(r, 'dateCreated'),
        lastUpdated: _time(r, 'lastUpdated'),
        isGhost: false,
        customJsonMetadata: r.readNullable<String>('customJsonMetadata'),
        customGQLTags: r.readNullable<String>('customGQLTags'),
        isHidden: _bool(r, 'isHidden'),
      ),
  ];

  final vouched = {
    for (final r in await all(
      'SELECT DISTINCT folderId FROM $alias.folder_revisions',
    ))
      r.read<String>('folderId'),
  };

  final fileCount = (await all(
    'SELECT count(*) AS c FROM $alias.file_entries',
  ))
      .single
      .read<int>('c');

  // In the order the old reader met them, so the refusal names the same row.
  final foreign = await db.customSelect(
    'SELECT driveId FROM ('
    'SELECT driveId FROM $alias.folder_entries '
    'UNION ALL SELECT driveId FROM $alias.file_entries '
    'UNION ALL SELECT driveId FROM $alias.drive_revisions '
    'UNION ALL SELECT driveId FROM $alias.folder_revisions '
    'UNION ALL SELECT driveId FROM $alias.file_revisions '
    'UNION ALL SELECT driveId FROM $alias.licenses'
    ') WHERE driveId IS NOT ? LIMIT 1',
    variables: [Variable(drive.id)],
  ).get();

  return ArtifactForMerge(
    drive: drive,
    folders: folders,
    vouchedFolderIds: vouched,
    fileCount: fileCount,
    foreignDriveId:
        foreign.isEmpty ? null : foreign.single.read<String>('driveId'),
    // Through fromJson, not the constructor: it is the one place a coverage
    // claim is checked to be a real block range.
    coverage: DriveStateCoverage.fromJson({
      'blockStart': meta.read<int>('blockStart'),
      'blockEnd': meta.read<int>('blockEnd'),
    }),
    version: DriveStateFormatVersion.parse(meta.read<String>('version')),
    unconfirmedTransactions: await _unconfirmedTransactions(all, alias),
  );
}

/// `transaction_statuses`, checked against the rule a reader applies to it.
///
/// A row this build could not apply, or a duplicate id, means the artifact
/// was not written by a producer that follows the format, and the whole
/// artifact is refused rather than partly believed.
Future<Map<String, String>> _unconfirmedTransactions(
  Future<List<QueryRow>> Function(String sql) all,
  String alias,
) async {
  final statuses = <String, String>{};
  for (final r in await all(
    'SELECT s.id AS id, s.status AS status, '
    's.id IN (SELECT dataTxId FROM $alias.file_revisions) AS isData '
    'FROM $alias.transaction_statuses s',
  )) {
    final id = r.read<String>('id');
    final status = r.read<String>('status');
    if (importedTransactionStatus(
          carriedStatus: status,
          isDataTransaction: r.read<int>('isData') != 0,
        ) ==
        null) {
      throw DriveStateFormatException(
        DriveStateFormatError.malformed,
        'transaction $id is listed as "$status", which a reader cannot apply',
      );
    }
    if (statuses.containsKey(id)) {
      throw DriveStateFormatException(
        DriveStateFormatError.malformed,
        'transaction $id is listed twice',
      );
    }
    statuses[id] = status;
  }
  return statuses;
}

String _value(String column, {String from = ''}) =>
    // `isHidden` is the one integer read as a boolean: any non-zero value is
    // true, and drift writes true as 1.
    column == 'isHidden' ? '($from$column != 0)' : '$from$column';

/// Adds the rows of [table] the local database does not already hold.
///
/// For the revision tables and `licenses`: their keys contain their version,
/// so the artifact can only add (see the merge's class comment).
String artifactInsertOrIgnoreSql(String alias, String table) {
  final columns = artifactCopiedColumns[table]!;
  return 'INSERT OR IGNORE INTO main.$table (${columns.keys.join(', ')}) '
      'SELECT ${columns.keys.map(_value).join(', ')} '
      'FROM $alias.$table ORDER BY rowid';
}

/// The condition under which an artifact's file row is written: the local
/// row, if there is one, is not newer. `a` is the artifact's row.
const artifactFileWinsSql = 'NOT EXISTS (SELECT 1 FROM main.file_entries l '
    'WHERE l.id = a.id AND l.driveId = a.driveId '
    'AND l.lastUpdated > a.lastUpdated)';

/// Writes every artifact file row that wins, replacing the local one.
///
/// `path` is not carried; every reader writes it empty.
String artifactFileEntriesUpsertSql(String alias) {
  final columns = artifactCopiedColumns['file_entries']!;
  final names = [...columns.keys, 'path'];
  final values = [
    ...columns.keys.map((c) => _value(c, from: 'a.')),
    "''",
  ];
  final updates = names
      .where((c) => c != 'id' && c != 'driveId')
      .map((c) => '$c = excluded.$c')
      .join(', ');
  return 'INSERT INTO main.file_entries (${names.join(', ')}) '
      'SELECT ${values.join(', ')} FROM $alias.file_entries a '
      'WHERE $artifactFileWinsSql ORDER BY a.rowid '
      'ON CONFLICT(id, driveId) DO UPDATE SET $updates';
}

/// Derives `network_transactions` from the copied rows.
///
/// The rule `lib/sync/utils/network_transaction_utils.dart` and
/// `LicensesCompanionExtensions` apply, in the order the old merge offered
/// them, because the first row offered for an id is the one that lands:
///
///  * one per drive, folder and file revision for its metadata transaction,
///    and one per file revision for its data transaction, dated by
///    `transactionDateCreated`;
///  * one per licence, dated by `dateCreated`.
///
/// Each is `confirmed` unless `transaction_statuses` lists it, in which case
/// [importedTransactionStatus] decides. A row the local database already
/// holds keeps its own status.
String artifactNetworkTransactionsSql(String alias) =>
    'INSERT OR IGNORE INTO main.network_transactions '
    '(id, status, dateCreated, transactionDateCreated) '
    'SELECT t.id, '
    "CASE WHEN s.id IS NULL THEN 'confirmed' "
    'WHEN t.id IN (SELECT dataTxId FROM $alias.file_revisions) '
    "THEN 'pending' ELSE s.status END, "
    "coalesce(t.dateCreated, CAST(strftime('%s', 'now') AS INTEGER)), "
    't.transactionDateCreated '
    'FROM ('
    'SELECT 1 AS source, rowid AS position, 0 AS part, metadataTxId AS id, '
    'NULL AS dateCreated, dateCreated AS transactionDateCreated '
    'FROM $alias.drive_revisions '
    'UNION ALL SELECT 2, rowid, 0, metadataTxId, NULL, dateCreated '
    'FROM $alias.folder_revisions '
    'UNION ALL SELECT 3, rowid, 0, metadataTxId, NULL, dateCreated '
    'FROM $alias.file_revisions '
    'UNION ALL SELECT 3, rowid, 1, dataTxId, NULL, dateCreated '
    'FROM $alias.file_revisions '
    'UNION ALL SELECT 4, rowid, 0, licenseTxId, dateCreated, NULL '
    'FROM $alias.licenses'
    ') t LEFT JOIN $alias.transaction_statuses s ON s.id = t.id '
    'ORDER BY t.source, t.position, t.part';
