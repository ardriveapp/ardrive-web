import 'package:ardrive/models/models.dart';
import 'package:drift/drift.dart';
import 'package:equatable/equatable.dart';

/// Exports one drive's current state from the local database, and converts it
/// to and from the artifact's section format.
///
/// Three rules from `docs/DRIVE_STATE_ARTIFACT.md` shape everything here:
///
///  * **No key material may leave the database** (§2.1). Every table is read
///    through a projection that names its columns, so a column added by a
///    later migration is invisible to the export until someone classifies it.
///    `profiles` is not referenced at all. Decision D7 chose this over the
///    database views the proposal wanted, because views need a schema
///    migration; the projections plus [driveStateExportedColumns] /
///    [driveStateWithheldColumns] are what a drift test can assert against the
///    live schema.
///  * **Current state only** (decision D2). `file_entries` and
///    `folder_entries` hold one row per entity; no revision's *contents* are
///    read. History stays available through snapshots and GraphQL.
///  * **Only what came from the chain.** Those two tables also hold rows this
///    client invented locally, and publishing one is not recoverable - see
///    [_folderEntryCameFromChain]. The revision tables are read for existence
///    alone, as the discriminator.

/// The section format this build writes, and the newest it can read.
///
/// Per §6 this bumps only when an older reader would *misinterpret* a payload,
/// never for an added section or field — bumping on additions would lock out
/// clients that could have used most of the artifact.
const int driveStateFormatVersion = 1;

/// Section names. They match the table each section carries so that a reader
/// in another language can map them without knowing this app's schema.
const String driveSectionName = 'drives';
const String folderEntriesSectionName = 'folder_entries';
const String fileEntriesSectionName = 'file_entries';

const String _sectionsKey = 'sections';
const String _versionKey = 'version';
const String _rowsKey = 'rows';
const String _coverageKey = 'coverage';
const String _blockStartKey = 'blockStart';
const String _blockEndKey = 'blockEnd';

/// Why a payload could not be read. Enumerated because §7 requires
/// "no artifact was used" and "an artifact was rejected because X" to never
/// look the same in a log.
enum DriveStateFormatError {
  /// The payload declares a version this build does not understand. Callers
  /// must treat this as "ignore the artifact", never as a corrupt drive.
  unsupportedVersion,

  /// A section, row or required field was missing or the wrong shape.
  malformed,
}

class DriveStateFormatException implements Exception {
  final DriveStateFormatError error;
  final String message;

  const DriveStateFormatException(this.error, this.message);

  @override
  String toString() => 'DriveStateFormatException(${error.name}): $message';
}

/// The range of block heights the payload accounts for.
///
/// This is the artifact's **coverage claim**, and it lives in the payload
/// rather than only in the `Block-Start` / `Block-End` tags because the
/// payload is what the owner signs (§2.2). The tags are not: a transaction
/// tag is chosen by whoever submits the transaction, so anyone who copies an
/// owner's artifact bytes verbatim can re-publish them under any coverage
/// they like. Those bytes still verify - they are the owner's - and an
/// importer that took its watermark from the tag would advance the drive past
/// a range nothing ever synced, which is the silent drop in
/// `SYNC_SKIPPED_ENTITY_PERSISTENCE.md`.
///
/// So the tags stay, because discovery has to order candidates without
/// downloading them, and the importer cross-checks them against this before
/// believing either. Same shape as `Drive-Id` and `Entity-Count`: the tag says
/// what to expect, the signed body decides.
class DriveStateCoverage extends Equatable {
  /// The lowest block height accounted for. Always 0 for anything this client
  /// publishes (§3.4) - carried rather than assumed, because an incremental
  /// artifact is a format the importer's range arithmetic already handles, and
  /// a coverage claim missing its lower bound could not be checked.
  final int blockStart;

  /// The highest block height accounted for: the producer's own sync
  /// watermark at the moment of export, and nothing else. A producer that
  /// claimed more than it had synced would be publishing the very gap this
  /// field exists to close.
  final int blockEnd;

  const DriveStateCoverage({
    required this.blockStart,
    required this.blockEnd,
  });

  Map<String, dynamic> toJson() => {
        _blockStartKey: blockStart,
        _blockEndKey: blockEnd,
      };

  factory DriveStateCoverage.fromJson(Map<String, dynamic> json) {
    final coverage = DriveStateCoverage(
      blockStart: _required(json, _blockStartKey),
      blockEnd: _required(json, _blockEndKey),
    );

    // A range that runs backwards, or below the genesis block, is not a
    // coverage claim any producer could honestly make. Rejecting it here costs
    // nothing and keeps the arithmetic downstream working on a real interval.
    if (coverage.blockStart < 0 ||
        coverage.blockEnd < 0 ||
        coverage.blockStart > coverage.blockEnd) {
      throw DriveStateFormatException(
        DriveStateFormatError.malformed,
        'coverage [${coverage.blockStart}, ${coverage.blockEnd}] is not a '
        'block range',
      );
    }

    return coverage;
  }

  @override
  List<Object?> get props => [blockStart, blockEnd];

  @override
  String toString() => '[$blockStart, $blockEnd]';
}

/// One drive's current state, as an object graph.
class DriveStateExport extends Equatable {
  final ExportedDrive drive;
  final List<ExportedFolderEntry> folders;
  final List<ExportedFileEntry> files;

  /// What range of the drive's history the rows above account for. Signed
  /// with them; see [DriveStateCoverage].
  final DriveStateCoverage coverage;

  const DriveStateExport({
    required this.drive,
    required this.folders,
    required this.files,
    required this.coverage,
  });

  /// The number of entities the payload carries, which the entity's
  /// `Entity-Count` tag declares so that an importer can prove the body meant
  /// what the tags promised (§3.2).
  int get entityCount => folders.length + files.length + 1;

  Map<String, dynamic> toJson() => {
        _versionKey: driveStateFormatVersion,
        _coverageKey: coverage.toJson(),
        _sectionsKey: {
          driveSectionName: {
            _rowsKey: [drive.toJson()],
          },
          folderEntriesSectionName: {
            _rowsKey: folders.map((f) => f.toJson()).toList(),
          },
          fileEntriesSectionName: {
            _rowsKey: files.map((f) => f.toJson()).toList(),
          },
        },
      };

  /// The exact inverse of [toJson].
  ///
  /// Sections and fields this build does not know are ignored rather than
  /// rejected (§6): a reader takes what it knows, so a producer can add a
  /// section without stranding older clients.
  factory DriveStateExport.fromJson(Map<String, dynamic> json) {
    final version = json[_versionKey];
    if (version is! int) {
      throw const DriveStateFormatException(
        DriveStateFormatError.malformed,
        'payload has no integer "$_versionKey"',
      );
    }
    if (version > driveStateFormatVersion) {
      throw DriveStateFormatException(
        DriveStateFormatError.unsupportedVersion,
        'payload version $version is newer than $driveStateFormatVersion',
      );
    }

    final sections = _asMap(json[_sectionsKey], _sectionsKey);
    final driveRows = _rowsOf(sections, driveSectionName);
    if (driveRows.length != 1) {
      throw DriveStateFormatException(
        DriveStateFormatError.malformed,
        'the "$driveSectionName" section holds ${driveRows.length} rows, '
        'expected exactly one',
      );
    }

    return DriveStateExport(
      // Required, not optional. The reader that treated an absent coverage
      // claim as "trust the tag" would be the reader this field was added to
      // remove, and no artifact exists that predates it: nothing has been
      // published on chain. A payload without one is malformed, which means
      // the drive syncs the ordinary way.
      coverage: DriveStateCoverage.fromJson(
        _asMap(json[_coverageKey], _coverageKey),
      ),
      drive: ExportedDrive.fromJson(driveRows.single),
      folders: _rowsOf(sections, folderEntriesSectionName)
          .map(ExportedFolderEntry.fromJson)
          .toList(),
      files: _rowsOf(sections, fileEntriesSectionName)
          .map(ExportedFileEntry.fromJson)
          .toList(),
    );
  }

  @override
  List<Object?> get props => [drive, folders, files, coverage];
}

/// Reads one drive's current state.
///
/// Only the drive named by [driveId] is touched: the artifact covers one
/// drive, but the database holds every drive the user has attached.
///
/// Rows come back ordered by primary key so that two exports of the same state
/// serialise to the same bytes. The payload is signed (§2.2), and a signature
/// over a non-deterministic encoding is a signature nobody can reproduce.
Future<DriveStateExport> exportDriveState(
  DriveDao driveDao,
  String driveId,
) async {
  // One snapshot, not four reads.
  //
  // The coverage claim below says what the rows in this payload account for,
  // so it has to be read from the same state the rows were. Sync commits in
  // batches; a watermark read after a batch landed would claim blocks whose
  // rows this export did not carry - which is precisely the lie the importer
  // trusts when it advances a consumer's watermark.
  return driveDao.transaction(() async {
    final driveRow =
        await driveStateDriveQuery(driveDao, driveId).getSingleOrNull();

    if (driveRow == null) {
      throw StateError('cannot export drive $driveId: no such drive');
    }

    // Read on its own rather than folded into [driveStateDriveQuery], because
    // that query's projection is the payload's and `lastBlockHeight` is
    // withheld from it - see [_withheldDriveColumns]. Adding it there would
    // put a withheld column in the statement whose SQL is the leak guarantee.
    final watermark =
        await driveStateCoverageQuery(driveDao, driveId).getSingleOrNull();

    final folderRows =
        await driveStateFolderEntriesQuery(driveDao, driveId).get();
    final fileRows = await driveStateFileEntriesQuery(driveDao, driveId).get();

    return DriveStateExport(
      // The producer's watermark is the only honest answer to "what does this
      // artifact account for": the rows above are the drive as this client had
      // synced it, and it had synced it to here. A drive that has never synced
      // covers nothing, which is a truthful [0, 0] rather than a refusal - the
      // importer's range arithmetic already declines to advance on it.
      coverage: DriveStateCoverage(
        blockStart: 0,
        blockEnd: watermark?.read(driveDao.drives.lastBlockHeight) ?? 0,
      ),
      drive: ExportedDrive._fromRow(driveRow, driveDao.drives),
      folders: folderRows
          .map((row) =>
              ExportedFolderEntry._fromRow(row, driveDao.folderEntries))
          .toList(),
      files: fileRows
          .map((row) => ExportedFileEntry._fromRow(row, driveDao.fileEntries))
          .toList(),
    );
  });
}

// The statements [exportDriveState] runs: one per payload section, plus the
// coverage read.
//
// They are built here rather than inline so a test can assert the SQL they
// generate. The key-material guarantee is a property of that SQL - a
// `selectOnly` that names every column it reads - and a test that reads the
// query text proves the mechanism, where a test that greps the encoded payload
// only proves one rendering of one value.

/// The `drives` row the export reads.
JoinedSelectStatement driveStateDriveQuery(DriveDao driveDao, String driveId) {
  final drives = driveDao.drives;
  return driveDao.selectOnly(drives)
    ..addColumns(driveStateExportedColumns(drives))
    ..where(drives.id.equals(driveId));
}

/// The producer's sync watermark, which becomes the coverage claim.
///
/// Deliberately not part of [driveStateDriveQuery]. `lastBlockHeight` is
/// withheld from the drive row (a row column is adopted wholesale by the
/// importer's merge, and the consumer's own watermark is not the producer's to
/// set), and the payload-section queries are the ones whose generated SQL is
/// asserted to name no withheld column. The coverage claim is a different
/// thing that happens to read the same number, so it reads it separately.
JoinedSelectStatement driveStateCoverageQuery(
  DriveDao driveDao,
  String driveId,
) {
  final drives = driveDao.drives;
  return driveDao.selectOnly(drives)
    ..addColumns([drives.lastBlockHeight])
    ..where(drives.id.equals(driveId));
}

/// The drive's chain-derived `folder_entries` rows, ordered by id.
JoinedSelectStatement driveStateFolderEntriesQuery(
  DriveDao driveDao,
  String driveId,
) {
  final folderEntries = driveDao.folderEntries;
  return driveDao.selectOnly(folderEntries)
    ..addColumns(driveStateExportedColumns(folderEntries))
    ..where(folderEntries.driveId.equals(driveId) &
        _folderEntryCameFromChain(driveDao))
    ..orderBy([OrderingTerm.asc(folderEntries.id)]);
}

/// The drive's chain-derived `file_entries` rows, ordered by id.
JoinedSelectStatement driveStateFileEntriesQuery(
  DriveDao driveDao,
  String driveId,
) {
  final fileEntries = driveDao.fileEntries;
  return driveDao.selectOnly(fileEntries)
    ..addColumns(driveStateExportedColumns(fileEntries))
    ..where(
        fileEntries.driveId.equals(driveId) & _fileEntryCameFromChain(driveDao))
    ..orderBy([OrderingTerm.asc(fileEntries.id)]);
}

/// Whether a `folder_entries` row came off the chain, rather than being
/// invented by this client.
///
/// Not every row in that table is a folder that exists on Arweave:
///
///  * **Ghost folders.** When a file names a parent whose own metadata was
///    never found, sync writes a stand-in row: named after its own uuid,
///    parented to the drive root, `isGhost: true`, stamped `DateTime.now()`
///    (`SyncRepository`). A normal state, not corruption - but a local guess.
///  * **Root folder placeholders.** `DriveDao._rootFolderPlaceholder` inserts
///    a row for a discovered drive's root folder so the drive can be opened
///    before its metadata arrives. It sets no timestamp, so SQLite's
///    `strftime('%s','now')` default applies, and it deliberately sets no
///    `isGhost` either: the upsert that lands real metadata leaves absent
///    columns alone, so the flag would stick forever. It therefore carries no
///    marker of its own - which is why filtering on `isGhost` is not enough.
///
/// Both are stamped with *now*, while a synced row carries its revision's
/// chain commit time. Since the importer keeps a local row only when it is
/// strictly newer than the artifact's, a fabricated row always wins: an
/// artifact carrying one would replace a correctly synced folder with a
/// uuid-named, root-parented ghost in every client that imported it, and an
/// artifact cannot be recalled.
///
/// A revision is the honest discriminator, because one is written only when
/// real metadata is read - by sync, or by the local action that uploaded it.
/// It is the same signal `DriveDetailCubit` uses to tell a genuinely empty
/// drive from one that has never synced.
Expression<bool> _folderEntryCameFromChain(DriveDao driveDao) {
  final entries = driveDao.folderEntries;
  final revisions = driveDao.folderRevisions;

  return existsQuery(
    driveDao.selectOnly(revisions)
      ..addColumns([revisions.folderId])
      ..where(revisions.folderId.equalsExp(entries.id) &
          revisions.driveId.equalsExp(entries.driveId)),
  );
}

/// The same discriminator for `file_entries`.
///
/// No code path fabricates a file row today, so this filters nothing out of a
/// healthy database. It is applied anyway because the rule the export needs is
/// "publish what the chain said", not "publish what no known bug wrote", and
/// the next stand-in row should be dropped by a filter that already exists
/// rather than by one nobody remembered to add.
Expression<bool> _fileEntryCameFromChain(DriveDao driveDao) {
  final entries = driveDao.fileEntries;
  final revisions = driveDao.fileRevisions;

  return existsQuery(
    driveDao.selectOnly(revisions)
      ..addColumns([revisions.fileId])
      ..where(revisions.fileId.equalsExp(entries.id) &
          revisions.driveId.equalsExp(entries.driveId)),
  );
}

/// Every table the export may read, by its name in the schema - which is also
/// its section name on the wire.
///
/// One list, consulted by [driveStateExportedColumns],
/// [driveStateWithheldColumns] and by the drift guard test. A table that is
/// not named here is refused whatever anyone classifies, so a section added
/// for a fourth table cannot slip past a guard that only knew about three.
///
/// Adding to it is a decision, not a formality. The artifact covers *one*
/// drive and is encrypted with *that* drive's key, so an exported table must
/// be scopable to a single drive: the near tables that look tempting -
/// `network_transactions`, `arns_records`, `ant_records` - have no `driveId`
/// column at all, and exporting one would publish rows about the user's other
/// drives to everyone holding this drive's key. `profiles` holds the wallet
/// and is never exportable at any scope.
const List<String> _exportedTableNames = [
  driveSectionName,
  folderEntriesSectionName,
  fileEntriesSectionName,
];

/// The tables of [_exportedTableNames], resolved against a live database.
///
/// The guard test iterates this, so whatever the export is willing to read is
/// exactly what has to be classified column by column.
List<TableInfo> driveStateExportedTables(GeneratedDatabase db) => [
      for (final name in _exportedTableNames)
        db.allTables.firstWhere((t) => t.actualTableName == name),
    ];

/// The columns of [table] the export reads, in wire order.
///
/// Exposed so a test can assert the projection against the live schema. A
/// migration that adds a column to an exported table makes
/// `exported + withheld` disagree with the table's own column list, and the
/// test fails until the new column is deliberately placed in one or the other.
List<GeneratedColumn> driveStateExportedColumns(TableInfo table) =>
    _classify(table).exported;

/// The columns of [table] the export deliberately does not read.
List<GeneratedColumn> driveStateWithheldColumns(TableInfo table) =>
    _classify(table).withheld;

/// Both halves of one table's classification, decided together.
///
/// Together, because two lists maintained apart drift apart: the guarantee is
/// that `exported + withheld` accounts for every column of the table, and a
/// column can only go missing from both if the two are written in different
/// places.
///
/// Refusing an unlisted table is the point of this function, not an accident
/// of falling off the end of it: `profiles`, the revision tables and every
/// other table in the schema throw here.
({List<GeneratedColumn> exported, List<GeneratedColumn> withheld}) _classify(
  TableInfo table,
) {
  if (_exportedTableNames.contains(table.actualTableName)) {
    if (table is Drives) {
      return (
        exported: _exportedDriveColumns(table),
        withheld: _withheldDriveColumns(table),
      );
    }
    if (table is FolderEntries) {
      return (exported: _exportedFolderEntryColumns(table), withheld: const []);
    }
    if (table is FileEntries) {
      return (exported: _exportedFileEntryColumns(table), withheld: const []);
    }
  }
  throw ArgumentError('${table.actualTableName} is not an exported table');
}

/// The drive key, wrapped in the profile key, and the two columns needed to
/// unwrap it. Publishing any of these is permanent — Arweave has no delete —
/// so they are named here and excluded from the projection by construction,
/// not filtered out after the fact.
List<GeneratedColumn> _withheldDriveColumns(Drives t) => [
      t.encryptedKey,
      t.driveKeyGenerated,
      t.keyEncryptionIv,
      // Not secret, but not portable, and unsafe to adopt.
      //
      // `syncCursor` is an opaque GraphQL cursor issued by one gateway's
      // indexer. It means nothing to a different endpoint, so an importer
      // that adopted it would resume pagination from an arbitrary position.
      //
      // `lastBlockHeight` is withheld *as a column of the drive row*, which
      // is not the same thing as the artifact's coverage. A row column is
      // adopted wholesale by the merge, unchecked against anything; the
      // coverage claim is a container-level field that the importer refuses
      // unless the `Block-End` tag agrees with it, and then only advances the
      // watermark across ground the claim actually covers. The value behind
      // both is the same integer - see [DriveStateCoverage] - and the
      // difference is entirely in what a reader is allowed to do with it. A
      // watermark adopted without those checks is the drive advancing past
      // unsynced entities: the silent drop in
      // SYNC_SKIPPED_ENTITY_PERSISTENCE.md.
      t.syncCursor,
      t.lastBlockHeight,
    ];

List<GeneratedColumn> _exportedDriveColumns(Drives t) => [
      t.id,
      t.rootFolderId,
      t.ownerAddress,
      t.name,
      t.privacy,
      t.bundledIn,
      t.customJsonMetadata,
      t.customGQLTags,
      t.isHidden,
      t.signatureType,
      t.dateCreated,
      t.lastUpdated,
    ];

List<GeneratedColumn> _exportedFolderEntryColumns(FolderEntries t) => [
      t.id,
      t.driveId,
      t.name,
      t.parentFolderId,
      t.path,
      t.dateCreated,
      t.lastUpdated,
      t.isGhost,
      t.customJsonMetadata,
      t.customGQLTags,
      t.isHidden,
    ];

List<GeneratedColumn> _exportedFileEntryColumns(FileEntries t) => [
      t.id,
      t.driveId,
      t.name,
      t.parentFolderId,
      t.path,
      t.size,
      t.lastModifiedDate,
      t.dataContentType,
      t.dataTxId,
      t.licenseTxId,
      t.bundledIn,
      t.thumbnail,
      t.pinnedDataOwnerAddress,
      t.customJsonMetadata,
      t.customGQLTags,
      t.isHidden,
      t.dateCreated,
      t.lastUpdated,
      t.assignedNames,
      t.fallbackTxId,
      t.originalOwner,
      t.importSource,
    ];

/// A `drives` row with the key material structurally absent.
///
/// This is not [Drive] with three fields left null — it is a type that has no
/// place to put them, so no later code can populate them by accident.
class ExportedDrive extends Equatable {
  final String id;
  final String rootFolderId;
  final String ownerAddress;
  final String name;
  final String privacy;
  final String? bundledIn;
  final String? customJsonMetadata;
  final String? customGQLTags;
  final bool isHidden;
  final String? signatureType;
  final DateTime dateCreated;
  final DateTime lastUpdated;

  const ExportedDrive({
    required this.id,
    required this.rootFolderId,
    required this.ownerAddress,
    required this.name,
    required this.privacy,
    required this.bundledIn,
    required this.customJsonMetadata,
    required this.customGQLTags,
    required this.isHidden,
    required this.signatureType,
    required this.dateCreated,
    required this.lastUpdated,
  });

  factory ExportedDrive._fromRow(TypedResult row, Drives t) => ExportedDrive(
        id: row.read(t.id)!,
        rootFolderId: row.read(t.rootFolderId)!,
        ownerAddress: row.read(t.ownerAddress)!,
        name: row.read(t.name)!,
        privacy: row.read(t.privacy)!,
        bundledIn: row.read(t.bundledIn),
        customJsonMetadata: row.read(t.customJsonMetadata),
        customGQLTags: row.read(t.customGQLTags),
        isHidden: row.read(t.isHidden)!,
        signatureType: row.read(t.signatureType),
        dateCreated: row.read(t.dateCreated)!,
        lastUpdated: row.read(t.lastUpdated)!,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'rootFolderId': rootFolderId,
        'ownerAddress': ownerAddress,
        'name': name,
        'privacy': privacy,
        'bundledIn': bundledIn,
        'customJsonMetadata': customJsonMetadata,
        'customGQLTags': customGQLTags,
        'isHidden': isHidden,
        'signatureType': signatureType,
        'dateCreated': _dateToJson(dateCreated),
        'lastUpdated': _dateToJson(lastUpdated),
      };

  factory ExportedDrive.fromJson(Map<String, dynamic> json) => ExportedDrive(
        id: _required(json, 'id'),
        rootFolderId: _required(json, 'rootFolderId'),
        ownerAddress: _required(json, 'ownerAddress'),
        name: _required(json, 'name'),
        privacy: _required(json, 'privacy'),
        bundledIn: _optional(json, 'bundledIn'),
        customJsonMetadata: _optional(json, 'customJsonMetadata'),
        customGQLTags: _optional(json, 'customGQLTags'),
        isHidden: _required(json, 'isHidden'),
        signatureType: _optional(json, 'signatureType'),
        dateCreated: _requiredDate(json, 'dateCreated'),
        lastUpdated: _requiredDate(json, 'lastUpdated'),
      );

  @override
  List<Object?> get props => [
        id,
        rootFolderId,
        ownerAddress,
        name,
        privacy,
        bundledIn,
        customJsonMetadata,
        customGQLTags,
        isHidden,
        signatureType,
        dateCreated,
        lastUpdated,
      ];
}

/// A `folder_entries` row.
class ExportedFolderEntry extends Equatable {
  final String id;
  final String driveId;
  final String name;
  final String? parentFolderId;
  final String path;
  final DateTime dateCreated;
  final DateTime lastUpdated;
  final bool isGhost;
  final String? customJsonMetadata;
  final String? customGQLTags;
  final bool isHidden;

  const ExportedFolderEntry({
    required this.id,
    required this.driveId,
    required this.name,
    required this.parentFolderId,
    required this.path,
    required this.dateCreated,
    required this.lastUpdated,
    required this.isGhost,
    required this.customJsonMetadata,
    required this.customGQLTags,
    required this.isHidden,
  });

  factory ExportedFolderEntry._fromRow(TypedResult row, FolderEntries t) =>
      ExportedFolderEntry(
        id: row.read(t.id)!,
        driveId: row.read(t.driveId)!,
        name: row.read(t.name)!,
        parentFolderId: row.read(t.parentFolderId),
        path: row.read(t.path)!,
        dateCreated: row.read(t.dateCreated)!,
        lastUpdated: row.read(t.lastUpdated)!,
        isGhost: row.read(t.isGhost)!,
        customJsonMetadata: row.read(t.customJsonMetadata),
        customGQLTags: row.read(t.customGQLTags),
        isHidden: row.read(t.isHidden)!,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'driveId': driveId,
        'name': name,
        'parentFolderId': parentFolderId,
        'path': path,
        'dateCreated': _dateToJson(dateCreated),
        'lastUpdated': _dateToJson(lastUpdated),
        'isGhost': isGhost,
        'customJsonMetadata': customJsonMetadata,
        'customGQLTags': customGQLTags,
        'isHidden': isHidden,
      };

  factory ExportedFolderEntry.fromJson(Map<String, dynamic> json) =>
      ExportedFolderEntry(
        id: _required(json, 'id'),
        driveId: _required(json, 'driveId'),
        name: _required(json, 'name'),
        parentFolderId: _optional(json, 'parentFolderId'),
        path: _required(json, 'path'),
        dateCreated: _requiredDate(json, 'dateCreated'),
        lastUpdated: _requiredDate(json, 'lastUpdated'),
        isGhost: _required(json, 'isGhost'),
        customJsonMetadata: _optional(json, 'customJsonMetadata'),
        customGQLTags: _optional(json, 'customGQLTags'),
        isHidden: _required(json, 'isHidden'),
      );

  @override
  List<Object?> get props => [
        id,
        driveId,
        name,
        parentFolderId,
        path,
        dateCreated,
        lastUpdated,
        isGhost,
        customJsonMetadata,
        customGQLTags,
        isHidden,
      ];
}

/// A `file_entries` row.
class ExportedFileEntry extends Equatable {
  final String id;
  final String driveId;
  final String name;
  final String parentFolderId;
  final String path;
  final int size;
  final DateTime lastModifiedDate;
  final String? dataContentType;
  final String dataTxId;
  final String? licenseTxId;
  final String? bundledIn;
  final String? thumbnail;
  final String? pinnedDataOwnerAddress;
  final String? customJsonMetadata;
  final String? customGQLTags;
  final bool isHidden;
  final DateTime dateCreated;
  final DateTime lastUpdated;
  final String? assignedNames;
  final String? fallbackTxId;
  final String? originalOwner;
  final String? importSource;

  const ExportedFileEntry({
    required this.id,
    required this.driveId,
    required this.name,
    required this.parentFolderId,
    required this.path,
    required this.size,
    required this.lastModifiedDate,
    required this.dataContentType,
    required this.dataTxId,
    required this.licenseTxId,
    required this.bundledIn,
    required this.thumbnail,
    required this.pinnedDataOwnerAddress,
    required this.customJsonMetadata,
    required this.customGQLTags,
    required this.isHidden,
    required this.dateCreated,
    required this.lastUpdated,
    required this.assignedNames,
    required this.fallbackTxId,
    required this.originalOwner,
    required this.importSource,
  });

  factory ExportedFileEntry._fromRow(TypedResult row, FileEntries t) =>
      ExportedFileEntry(
        id: row.read(t.id)!,
        driveId: row.read(t.driveId)!,
        name: row.read(t.name)!,
        parentFolderId: row.read(t.parentFolderId)!,
        path: row.read(t.path)!,
        size: row.read(t.size)!,
        lastModifiedDate: row.read(t.lastModifiedDate)!,
        dataContentType: row.read(t.dataContentType),
        dataTxId: row.read(t.dataTxId)!,
        licenseTxId: row.read(t.licenseTxId),
        bundledIn: row.read(t.bundledIn),
        thumbnail: row.read(t.thumbnail),
        pinnedDataOwnerAddress: row.read(t.pinnedDataOwnerAddress),
        customJsonMetadata: row.read(t.customJsonMetadata),
        customGQLTags: row.read(t.customGQLTags),
        isHidden: row.read(t.isHidden)!,
        dateCreated: row.read(t.dateCreated)!,
        lastUpdated: row.read(t.lastUpdated)!,
        assignedNames: row.read(t.assignedNames),
        fallbackTxId: row.read(t.fallbackTxId),
        originalOwner: row.read(t.originalOwner),
        importSource: row.read(t.importSource),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'driveId': driveId,
        'name': name,
        'parentFolderId': parentFolderId,
        'path': path,
        'size': size,
        'lastModifiedDate': _dateToJson(lastModifiedDate),
        'dataContentType': dataContentType,
        'dataTxId': dataTxId,
        'licenseTxId': licenseTxId,
        'bundledIn': bundledIn,
        'thumbnail': thumbnail,
        'pinnedDataOwnerAddress': pinnedDataOwnerAddress,
        'customJsonMetadata': customJsonMetadata,
        'customGQLTags': customGQLTags,
        'isHidden': isHidden,
        'dateCreated': _dateToJson(dateCreated),
        'lastUpdated': _dateToJson(lastUpdated),
        'assignedNames': assignedNames,
        'fallbackTxId': fallbackTxId,
        'originalOwner': originalOwner,
        'importSource': importSource,
      };

  factory ExportedFileEntry.fromJson(Map<String, dynamic> json) =>
      ExportedFileEntry(
        id: _required(json, 'id'),
        driveId: _required(json, 'driveId'),
        name: _required(json, 'name'),
        parentFolderId: _required(json, 'parentFolderId'),
        path: _required(json, 'path'),
        size: _required(json, 'size'),
        lastModifiedDate: _requiredDate(json, 'lastModifiedDate'),
        dataContentType: _optional(json, 'dataContentType'),
        dataTxId: _required(json, 'dataTxId'),
        licenseTxId: _optional(json, 'licenseTxId'),
        bundledIn: _optional(json, 'bundledIn'),
        thumbnail: _optional(json, 'thumbnail'),
        pinnedDataOwnerAddress: _optional(json, 'pinnedDataOwnerAddress'),
        customJsonMetadata: _optional(json, 'customJsonMetadata'),
        customGQLTags: _optional(json, 'customGQLTags'),
        isHidden: _required(json, 'isHidden'),
        dateCreated: _requiredDate(json, 'dateCreated'),
        lastUpdated: _requiredDate(json, 'lastUpdated'),
        assignedNames: _optional(json, 'assignedNames'),
        fallbackTxId: _optional(json, 'fallbackTxId'),
        originalOwner: _optional(json, 'originalOwner'),
        importSource: _optional(json, 'importSource'),
      );

  @override
  List<Object?> get props => [
        id,
        driveId,
        name,
        parentFolderId,
        path,
        size,
        lastModifiedDate,
        dataContentType,
        dataTxId,
        licenseTxId,
        bundledIn,
        thumbnail,
        pinnedDataOwnerAddress,
        customJsonMetadata,
        customGQLTags,
        isHidden,
        dateCreated,
        lastUpdated,
        assignedNames,
        fallbackTxId,
        originalOwner,
        importSource,
      ];
}

/// Dates travel as milliseconds since the epoch: an integer every language
/// reads the same way, unlike a formatted string whose timezone and precision
/// are a second thing to agree on.
int _dateToJson(DateTime date) => date.millisecondsSinceEpoch;

Map<String, dynamic> _asMap(Object? value, String what) {
  if (value is! Map) {
    throw DriveStateFormatException(
      DriveStateFormatError.malformed,
      '"$what" is ${value.runtimeType}, expected an object',
    );
  }
  return value.cast<String, dynamic>();
}

/// Reads a section's rows, treating an absent section as empty.
///
/// A section this build does not know is never looked up, so it is skipped
/// rather than rejected — the additive half of §6.
List<Map<String, dynamic>> _rowsOf(
  Map<String, dynamic> sections,
  String sectionName,
) {
  final section = sections[sectionName];
  if (section == null) return const [];

  final rows = _asMap(section, sectionName)[_rowsKey];
  if (rows is! List) {
    throw DriveStateFormatException(
      DriveStateFormatError.malformed,
      'section "$sectionName" has no "$_rowsKey" array',
    );
  }
  return rows
      .map((row) => _asMap(row, 'a row of "$sectionName"'))
      .toList(growable: false);
}

T _required<T extends Object>(Map<String, dynamic> row, String field) {
  final value = row[field];
  if (value is! T) {
    throw DriveStateFormatException(
      DriveStateFormatError.malformed,
      'field "$field" is ${value.runtimeType}, expected $T',
    );
  }
  return value;
}

T? _optional<T extends Object>(Map<String, dynamic> row, String field) {
  final value = row[field];
  if (value == null) return null;
  if (value is! T) {
    throw DriveStateFormatException(
      DriveStateFormatError.malformed,
      'field "$field" is ${value.runtimeType}, expected $T or null',
    );
  }
  return value;
}

DateTime _requiredDate(Map<String, dynamic> row, String field) =>
    DateTime.fromMillisecondsSinceEpoch(_required<int>(row, field));
