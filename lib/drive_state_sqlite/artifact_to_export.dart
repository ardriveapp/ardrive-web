/// Reads an attached artifact database into the same [DriveStateExport] shape
/// the JSON reader produced.
///
/// **Why this exists rather than a bulk `INSERT ... SELECT`.** The merge in
/// `drive_state_import.dart` is not a row copy: it materialises ghost folders
/// the way sync does, refuses a payload whose folder graph would contain a
/// cycle, keeps a local row that is newer than the artifact's, and derives
/// `network_transactions` through the helpers the rest of the app shares. Two
/// independent reviews found bugs in that logic; reimplementing it in SQL to
/// save a few hundred milliseconds would be trading a known-good guard for a
/// new one nobody has reviewed.
///
/// So the container changes and the merge does not. Rows come out of SQLite
/// instead of a JSON decoder — which is already the larger part of the win,
/// since there is no parse — and every guard downstream is the one that was
/// already tested.
///
/// Moving the bulk tables to `INSERT ... SELECT` afterwards is a
/// behaviour-neutral optimisation, and it should be done with the guards in
/// place and passing, not before.
library;

import 'package:ardrive/drive_state/data/drive_state_export.dart';
import 'package:ardrive/drive_state/domain/drive_state_format_version.dart';
import 'package:ardrive/drive_state_sqlite/drive_state_artifact_schema.dart';
import 'package:drift/drift.dart';

/// Drift stores `DATETIME` as unix **seconds** in this schema (no
/// `store_date_time_values_as_text` in `build.yaml`), and the artifact carries
/// the column through unchanged, so the artifact holds seconds too.
DateTime _time(QueryRow row, String column) =>
    DateTime.fromMillisecondsSinceEpoch(row.read<int>(column) * 1000);

bool _bool(QueryRow row, String column) => row.read<int>(column) != 0;

/// Reads the artifact attached as [alias] into a [DriveStateExport].
///
/// Assumes the caller has already refused anything whose `sqlite_master` is
/// not the frozen schema — these selects name columns that only exist because
/// that check passed.
///
/// **Coverage and version come from the artifact's own `meta` row, never from
/// the tags.** The payload is what is imported, and for a private drive it is
/// authenticated under the drive key; the tags are what an indexer reported.
/// The importer's whole reason for comparing the two is that difference.
/// Filling them in from the tags would make that comparison compare a value
/// with itself, and a mis-tagged artifact, the case the check exists for,
/// would pass.
Future<DriveStateExport> readArtifactAsExport(
  GeneratedDatabase db, {
  required String alias,
}) async {
  Future<List<QueryRow>> all(String table) =>
      db.customSelect('SELECT * FROM $alias.$table').get().then(
            (rows) => rows.map((r) => QueryRow(r.data, db)).toList(),
          );

  final driveRow = (await all('drives')).single;
  final meta = (await all('meta')).single;

  return DriveStateExport(
    drive: ExportedDrive(
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
    ),
    folders: [
      for (final r in await all('folder_entries'))
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
    ],
    files: [
      for (final r in await all('file_entries'))
        ExportedFileEntry(
          id: r.read<String>('id'),
          driveId: r.read<String>('driveId'),
          name: r.read<String>('name'),
          parentFolderId: r.read<String>('parentFolderId'),
          path: '',
          size: r.read<int>('size'),
          lastModifiedDate: _time(r, 'lastModifiedDate'),
          dataContentType: r.readNullable<String>('dataContentType'),
          dataTxId: r.read<String>('dataTxId'),
          licenseTxId: r.readNullable<String>('licenseTxId'),
          bundledIn: r.readNullable<String>('bundledIn'),
          thumbnail: r.readNullable<String>('thumbnail'),
          pinnedDataOwnerAddress:
              r.readNullable<String>('pinnedDataOwnerAddress'),
          customJsonMetadata: r.readNullable<String>('customJsonMetadata'),
          customGQLTags: r.readNullable<String>('customGQLTags'),
          isHidden: _bool(r, 'isHidden'),
          dateCreated: _time(r, 'dateCreated'),
          lastUpdated: _time(r, 'lastUpdated'),
          assignedNames: r.readNullable<String>('assignedNames'),
          fallbackTxId: r.readNullable<String>('fallbackTxId'),
          originalOwner: r.readNullable<String>('originalOwner'),
          importSource: r.readNullable<String>('importSource'),
        ),
    ],
    driveRevisions: [
      for (final r in await all('drive_revisions'))
        ExportedDriveRevision(
          driveId: r.read<String>('driveId'),
          rootFolderId: r.read<String>('rootFolderId'),
          ownerAddress: r.read<String>('ownerAddress'),
          name: r.read<String>('name'),
          privacy: r.read<String>('privacy'),
          metadataTxId: r.read<String>('metadataTxId'),
          dateCreated: _time(r, 'dateCreated'),
          action: r.read<String>('action'),
          bundledIn: r.readNullable<String>('bundledIn'),
          customJsonMetadata: r.readNullable<String>('customJsonMetadata'),
          customGQLTags: r.readNullable<String>('customGQLTags'),
          isHidden: _bool(r, 'isHidden'),
        ),
    ],
    folderRevisions: [
      for (final r in await all('folder_revisions'))
        ExportedFolderRevision(
          folderId: r.read<String>('folderId'),
          driveId: r.read<String>('driveId'),
          name: r.read<String>('name'),
          parentFolderId: r.readNullable<String>('parentFolderId'),
          metadataTxId: r.read<String>('metadataTxId'),
          dateCreated: _time(r, 'dateCreated'),
          action: r.read<String>('action'),
          customJsonMetadata: r.readNullable<String>('customJsonMetadata'),
          customGQLTags: r.readNullable<String>('customGQLTags'),
          isHidden: _bool(r, 'isHidden'),
        ),
    ],
    fileRevisions: [
      for (final r in await all('file_revisions'))
        ExportedFileRevision(
          fileId: r.read<String>('fileId'),
          driveId: r.read<String>('driveId'),
          name: r.read<String>('name'),
          parentFolderId: r.read<String>('parentFolderId'),
          size: r.read<int>('size'),
          lastModifiedDate: _time(r, 'lastModifiedDate'),
          dataContentType: r.readNullable<String>('dataContentType'),
          metadataTxId: r.read<String>('metadataTxId'),
          dataTxId: r.read<String>('dataTxId'),
          licenseTxId: r.readNullable<String>('licenseTxId'),
          thumbnail: r.readNullable<String>('thumbnail'),
          bundledIn: r.readNullable<String>('bundledIn'),
          dateCreated: _time(r, 'dateCreated'),
          customJsonMetadata: r.readNullable<String>('customJsonMetadata'),
          customGQLTags: r.readNullable<String>('customGQLTags'),
          action: r.read<String>('action'),
          pinnedDataOwnerAddress:
              r.readNullable<String>('pinnedDataOwnerAddress'),
          isHidden: _bool(r, 'isHidden'),
          assignedNames: r.readNullable<String>('assignedNames'),
          fallbackTxId: r.readNullable<String>('fallbackTxId'),
          originalOwner: r.readNullable<String>('originalOwner'),
          importSource: r.readNullable<String>('importSource'),
        ),
    ],
    licenses: [
      for (final r in await all('licenses'))
        ExportedLicense(
          fileId: r.read<String>('fileId'),
          driveId: r.read<String>('driveId'),
          dataTxId: r.read<String>('dataTxId'),
          licenseTxType: r.read<String>('licenseTxType'),
          licenseTxId: r.read<String>('licenseTxId'),
          bundledIn: r.readNullable<String>('bundledIn'),
          dateCreated: _time(r, 'dateCreated'),
          licenseType: r.read<String>('licenseType'),
          customGQLTags: r.readNullable<String>('customGQLTags'),
        ),
    ],
    // Through fromJson, not the constructor: it is the one place a coverage
    // claim is checked to be a real block range, and a reversed or negative
    // range from here would otherwise reach the merge. The caller turns the
    // throw into a refusal before anything is written.
    coverage: DriveStateCoverage.fromJson({
      'blockStart': meta.read<int>('blockStart'),
      'blockEnd': meta.read<int>('blockEnd'),
    }),
    version: DriveStateFormatVersion.parse(meta.read<String>('version')),
    unconfirmedTransactions: await _unconfirmedTransactions(all),
  );
}

/// `transaction_statuses`, checked against the rule a reader applies to it.
///
/// A row this build could not apply, or a duplicate id, means the artifact
/// was not written by a producer that follows the format, and the whole
/// artifact is refused rather than partly believed.
Future<Map<String, String>> _unconfirmedTransactions(
  Future<List<QueryRow>> Function(String table) all,
) async {
  final dataTxIds = {
    for (final r in await all('file_revisions')) r.read<String>('dataTxId'),
  };
  final statuses = <String, String>{};
  for (final r in await all('transaction_statuses')) {
    final id = r.read<String>('id');
    final status = r.read<String>('status');
    if (importedTransactionStatus(
          carriedStatus: status,
          isDataTransaction: dataTxIds.contains(id),
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
