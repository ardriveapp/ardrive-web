/// The drive state artifact, as a SQLite database rather than a serialisation
/// of rows.
///
/// This is the D12 counter-proposal to `docs/drive-state/DECISIONS.md` D1,
/// built so the two can be measured against each other on the same drive. See
/// `docs/drive-state/SQLITE_ARTIFACT.md`.
///
/// Two rules shape everything here.
///
/// **The schema is frozen, and it is not Drift's.** An artifact is not a copy
/// of this app's database; it is a format other clients read. Copying Drift's
/// tables would weld the wire format to `schemaVersion` — the thing the
/// proposal's §8 forbids — and it also measured *worst* of every option tried,
/// because the indexes are dead weight the reader throws away. So the tables
/// below are declared here, in full, and a reader compares an incoming file
/// against this exact text.
///
/// **Rows are copied in, never deleted out.** [artifactProjection] is the only
/// path data takes into an artifact, and it names every column explicitly.
/// `profiles` appears nowhere in this file. That is not an oversight to be
/// checked by a test — it is the mechanism: an artifact is built by selecting
/// these names into an *empty* database, so a column absent from this map
/// cannot reach one. There is no removal step, and therefore no removal step
/// that can be forgotten. `DROP TABLE` would not have been enough anyway;
/// dropped pages keep their bytes on the freelist unless `secure_delete` is
/// on, and it is off in the wasm build the browser runs.
library;

/// Bumped only when an older reader would *misinterpret* a payload, never for
/// an addition (proposal §6, D9). Mirrors the `State-Version` tag.
const artifactFormatVersion = '1.0';

/// Every table an artifact carries, in dependency order, with the exact DDL a
/// reader validates against.
///
/// Two of the app's tables are deliberately absent, and a reader must not
/// expect them:
///
/// * `network_transactions` is **derived on import** by
///   [regenerateNetworkTransactionsSql]. It is four columns, fully
///   reconstructible from the revisions, and it has no `driveId` — so carrying
///   it would publish rows about the producer's *other* drives to everyone
///   holding this drive's key.
/// * `arns_records` / `ant_records` are ARIO state, refetched from ARIO. The
///   drive-side fact — which names a file has — travels in `assignedNames`.
const artifactSchema = <String, String>{
  'meta': 'CREATE TABLE meta ('
      'version TEXT NOT NULL, '
      'driveId TEXT NOT NULL, '
      'ownerAddress TEXT NOT NULL, '
      'privacy TEXT NOT NULL, '
      'blockStart INTEGER NOT NULL, '
      'blockEnd INTEGER NOT NULL, '
      'entityCount INTEGER NOT NULL)',
  'drives': 'CREATE TABLE drives ('
      'id TEXT NOT NULL, '
      'rootFolderId TEXT NOT NULL, '
      'ownerAddress TEXT NOT NULL, '
      'name TEXT NOT NULL, '
      'privacy TEXT NOT NULL, '
      'bundledIn TEXT, '
      'customJsonMetadata TEXT, '
      'customGQLTags TEXT, '
      'isHidden INTEGER NOT NULL, '
      'signatureType TEXT, '
      'dateCreated INTEGER NOT NULL, '
      'lastUpdated INTEGER NOT NULL)',
  'folder_entries': 'CREATE TABLE folder_entries ('
      'id TEXT NOT NULL, '
      'driveId TEXT NOT NULL, '
      'name TEXT NOT NULL, '
      'parentFolderId TEXT, '
      'path TEXT NOT NULL, '
      'dateCreated INTEGER NOT NULL, '
      'lastUpdated INTEGER NOT NULL, '
      'isGhost INTEGER NOT NULL, '
      'customJsonMetadata TEXT, '
      'customGQLTags TEXT, '
      'isHidden INTEGER NOT NULL)',
  'file_entries': 'CREATE TABLE file_entries ('
      'id TEXT NOT NULL, '
      'driveId TEXT NOT NULL, '
      'name TEXT NOT NULL, '
      'parentFolderId TEXT NOT NULL, '
      'path TEXT NOT NULL, '
      'size INTEGER NOT NULL, '
      'lastModifiedDate INTEGER NOT NULL, '
      'dataContentType TEXT, '
      'dataTxId TEXT NOT NULL, '
      'licenseTxId TEXT, '
      'bundledIn TEXT, '
      'thumbnail TEXT, '
      'pinnedDataOwnerAddress TEXT, '
      'customJsonMetadata TEXT, '
      'customGQLTags TEXT, '
      'isHidden INTEGER NOT NULL, '
      'dateCreated INTEGER NOT NULL, '
      'lastUpdated INTEGER NOT NULL, '
      'assignedNames TEXT, '
      'fallbackTxId TEXT, '
      'originalOwner TEXT, '
      'importSource TEXT)',
  'drive_revisions': 'CREATE TABLE drive_revisions ('
      'driveId TEXT NOT NULL, '
      'rootFolderId TEXT NOT NULL, '
      'ownerAddress TEXT NOT NULL, '
      'name TEXT NOT NULL, '
      'privacy TEXT NOT NULL, '
      'metadataTxId TEXT NOT NULL, '
      'dateCreated INTEGER NOT NULL, '
      'action TEXT NOT NULL, '
      'bundledIn TEXT, '
      'customJsonMetadata TEXT, '
      'customGQLTags TEXT, '
      'isHidden INTEGER NOT NULL)',
  'folder_revisions': 'CREATE TABLE folder_revisions ('
      'folderId TEXT NOT NULL, '
      'driveId TEXT NOT NULL, '
      'name TEXT NOT NULL, '
      'parentFolderId TEXT, '
      'metadataTxId TEXT NOT NULL, '
      'dateCreated INTEGER NOT NULL, '
      'action TEXT NOT NULL, '
      'customJsonMetadata TEXT, '
      'customGQLTags TEXT, '
      'isHidden INTEGER NOT NULL)',
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
      'licenseTxId TEXT, '
      'thumbnail TEXT, '
      'bundledIn TEXT, '
      'dateCreated INTEGER NOT NULL, '
      'customJsonMetadata TEXT, '
      'customGQLTags TEXT, '
      'action TEXT NOT NULL, '
      'pinnedDataOwnerAddress TEXT, '
      'isHidden INTEGER NOT NULL, '
      'assignedNames TEXT, '
      'fallbackTxId TEXT, '
      'originalOwner TEXT, '
      'importSource TEXT)',
  'licenses': 'CREATE TABLE licenses ('
      'fileId TEXT NOT NULL, '
      'driveId TEXT NOT NULL, '
      'dataTxId TEXT NOT NULL, '
      'licenseTxType TEXT NOT NULL, '
      'licenseTxId TEXT NOT NULL, '
      'bundledIn TEXT, '
      'dateCreated INTEGER NOT NULL, '
      'licenseType TEXT NOT NULL, '
      'customGQLTags TEXT)',
};

/// The columns copied out of the local database, per table.
///
/// **What `drives` withholds, and why.** `encryptedKey`, `driveKeyGenerated`
/// and `keyEncryptionIv` are key material. `syncCursor` and `lastBlockHeight`
/// are the *local* sync watermark: they describe how far this client has read,
/// not what the drive is, and importing a stranger's watermark would advance a
/// reader past blocks it never saw.
///
/// Every other table travels whole. The order matters: `meta` is written last
/// by the exporter, from counts taken over the tables above it.
const artifactProjection = <String, List<String>>{
  'drives': [
    'id',
    'rootFolderId',
    'ownerAddress',
    'name',
    'privacy',
    'bundledIn',
    'customJsonMetadata',
    'customGQLTags',
    'isHidden',
    'signatureType',
    'dateCreated',
    'lastUpdated',
  ],
  'folder_entries': [
    'id',
    'driveId',
    'name',
    'parentFolderId',
    'path',
    'dateCreated',
    'lastUpdated',
    'isGhost',
    'customJsonMetadata',
    'customGQLTags',
    'isHidden',
  ],
  'file_entries': [
    'id',
    'driveId',
    'name',
    'parentFolderId',
    'path',
    'size',
    'lastModifiedDate',
    'dataContentType',
    'dataTxId',
    'licenseTxId',
    'bundledIn',
    'thumbnail',
    'pinnedDataOwnerAddress',
    'customJsonMetadata',
    'customGQLTags',
    'isHidden',
    'dateCreated',
    'lastUpdated',
    'assignedNames',
    'fallbackTxId',
    'originalOwner',
    'importSource',
  ],
  'drive_revisions': [
    'driveId',
    'rootFolderId',
    'ownerAddress',
    'name',
    'privacy',
    'metadataTxId',
    'dateCreated',
    'action',
    'bundledIn',
    'customJsonMetadata',
    'customGQLTags',
    'isHidden',
  ],
  'folder_revisions': [
    'folderId',
    'driveId',
    'name',
    'parentFolderId',
    'metadataTxId',
    'dateCreated',
    'action',
    'customJsonMetadata',
    'customGQLTags',
    'isHidden',
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
    'licenseTxId',
    'thumbnail',
    'bundledIn',
    'dateCreated',
    'customJsonMetadata',
    'customGQLTags',
    'action',
    'pinnedDataOwnerAddress',
    'isHidden',
    'assignedNames',
    'fallbackTxId',
    'originalOwner',
    'importSource',
  ],
  'licenses': [
    'fileId',
    'driveId',
    'dataTxId',
    'licenseTxType',
    'licenseTxId',
    'bundledIn',
    'dateCreated',
    'licenseType',
    'customGQLTags',
  ],
};

/// The column each table is filtered by when copying one drive out.
const _driveColumn = <String, String>{
  'drives': 'id',
};

String driveFilterColumn(String table) => _driveColumn[table] ?? 'driveId';

/// Columns that hold key material or local-only sync state and must never
/// appear in [artifactProjection]. Asserted by a test against the live schema,
/// so a migration that adds one to `drives` fails the build rather than
/// quietly widening what an export sees.
const withheldDriveColumns = <String>{
  'encryptedKey',
  'driveKeyGenerated',
  'keyEncryptionIv',
  'syncCursor',
  'lastBlockHeight',
};

/// Rebuilds `network_transactions` from the revisions an artifact carried.
///
/// Every transaction id an imported row references must exist here, because
/// `filesInFolderWithLicenseAndRevisionTransactions` INNER JOINs this table
/// through `file_revisions` — a file whose transaction is missing is dropped
/// from the listing entirely, and the drive renders an empty file list.
///
/// They land `confirmed` rather than the helpers' `pending`: an artifact's
/// coverage is the producer's own synced watermark, so importing tens of
/// thousands of pending rows would paint every file as pending and queue a
/// confirmation query per transaction.
///
/// `INSERT OR IGNORE` because the same id legitimately arrives from several
/// places — a file's metadata and data transactions, a licence, a bundle.
List<String> regenerateNetworkTransactionsSql(String artifactAlias) => [
      for (final (table, column) in const [
        ('drive_revisions', 'metadataTxId'),
        ('folder_revisions', 'metadataTxId'),
        ('file_revisions', 'metadataTxId'),
        ('file_revisions', 'dataTxId'),
        ('licenses', 'licenseTxId'),
      ])
        'INSERT OR IGNORE INTO network_transactions (id, status, dateCreated) '
            "SELECT DISTINCT $column, 'confirmed', dateCreated "
            'FROM $artifactAlias.$table WHERE $column IS NOT NULL',
    ];
