import 'package:ardrive/drive_state/domain/drive_state_format_version.dart';
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
///  * **Every revision, not the current state alone** (decision D2, reversed).
///    An earlier version of this file carried `drives`, `folder_entries` and
///    `file_entries` and nothing else, on the reasoning that entries are what
///    the explorer renders. That reasoning was false.
///    `filesInFolderWithLicenseAndRevisionTransactions`
///    (`lib/models/queries/drive_queries.drift`) - the query the file list
///    actually runs - **INNER JOINs** `network_transactions` twice, through a
///    correlated subselect that reads the newest `file_revisions` row for each
///    file. An entry with no revision behind it fails the ON condition and is
///    dropped, so an artifact of entries alone imports a drive that shows
///    nothing, in every folder, and does not heal: the import advances the
///    watermark past the range those revisions live in. So the revision tables
///    are on the wire, all of them, and every revision rather than the newest -
///    measured at 1.05 revisions per entity on a real 42k-file drive, which
///    buys the version history for about 5% more rows. `licenses` travels for
///    the same reason in the weaker form: its join is a LEFT JOIN, so a
///    missing row hides no file, it silently drops the licence.
///  * **`network_transactions` is derived, not carried.** It is four columns,
///    it has no `driveId` to scope it to this drive, and every row the file
///    list needs is reconstructible from the revisions that name it. The
///    importer rebuilds it through the same `lib/sync/utils/` helpers sync
///    uses, so there is one derivation with one set of tests rather than two.
///  * **Only what came from the chain.** `folder_entries` and `file_entries`
///    also hold rows this client invented locally, and publishing one is not
///    recoverable - see [_folderEntryCameFromChain]. A revision is the
///    discriminator, which is now also a section: the rows that travel and the
///    rows that vouch for them are the same set.

/// Section names. They match the table each section carries so that a reader
/// in another language can map them without knowing this app's schema.
const String driveSectionName = 'drives';
const String folderEntriesSectionName = 'folder_entries';
const String fileEntriesSectionName = 'file_entries';
const String driveRevisionsSectionName = 'drive_revisions';
const String folderRevisionsSectionName = 'folder_revisions';
const String fileRevisionsSectionName = 'file_revisions';
const String licensesSectionName = 'licenses';

/// Every section a payload of [DriveStateFormatVersion.current]'s major must
/// carry.
///
/// Order matters only for the message a refusal prints. Presence is what is
/// checked — see [DriveStateExport.fromJson] for why an absent section cannot
/// be read as an empty one.
const List<String> driveStateSectionNames = [
  driveSectionName,
  folderEntriesSectionName,
  fileEntriesSectionName,
  driveRevisionsSectionName,
  folderRevisionsSectionName,
  fileRevisionsSectionName,
  licensesSectionName,
];

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
  /// The payload declares a **readable but wrong** major version — a format
  /// this build could name and still cannot read, in either direction (§6).
  /// Callers must treat this as "ignore the artifact", never as a corrupt
  /// drive.
  ///
  /// A version this build cannot even *parse* is [malformed] instead. The two
  /// are different facts: this one says the artifact was written to a format
  /// whose number we understood and did not share, and that says nothing was
  /// established at all.
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

  /// Every revision of every entity above, oldest first within each entity.
  ///
  /// Not the newest per entity: the file details panel lists a file's whole
  /// history, and dropping the superseded rows to save 5% would publish an
  /// artifact that restores a drive with no history in it - permanently, since
  /// the range those revisions live in is one the importer's watermark then
  /// skips.
  final List<ExportedDriveRevision> driveRevisions;
  final List<ExportedFolderRevision> folderRevisions;
  final List<ExportedFileRevision> fileRevisions;

  /// The licences the user attached to their own files.
  final List<ExportedLicense> licenses;

  /// What range of the drive's history the rows above account for. Signed
  /// with them; see [DriveStateCoverage].
  final DriveStateCoverage coverage;

  /// The format version this payload declares, `major.minor` (§6).
  ///
  /// Inside the signature, unlike the `State-Version` tag that repeats it, so
  /// this is the copy an importer trusts and the tag is the hint it
  /// cross-checks — the same split, for the same reason, as
  /// [DriveStateCoverage] against `Block-Start`/`Block-End`.
  ///
  /// Defaulted rather than required because a producer has exactly one
  /// truthful answer — this build writes this build's format — and a required
  /// parameter would only be somewhere for a caller to pass something else.
  /// [DriveStateExport.fromJson] sets it from the wire, so a parsed payload
  /// carries what it declared rather than what this build assumes.
  final DriveStateFormatVersion version;

  const DriveStateExport({
    required this.drive,
    required this.folders,
    required this.files,
    required this.driveRevisions,
    required this.folderRevisions,
    required this.fileRevisions,
    required this.licenses,
    required this.coverage,
    this.version = DriveStateFormatVersion.current,
  });

  /// The number of **entities** the payload carries, which the entity's
  /// `Entity-Count` tag declares so that an importer can prove the body meant
  /// what the tags promised (§3.2).
  ///
  /// Entities, not rows. A revision is a version *of* an entity, not another
  /// entity, and a licence is an attachment to one - so neither is counted
  /// here even though both now travel. This is a contract, not a preference:
  /// the tag is written by [DriveStateCreationService], checked by
  /// [DriveStateImporter], and shown in the confirmation modal, and a build
  /// that counted revisions would reject every artifact written by a build
  /// that counted entities.
  int get entityCount => folders.length + files.length + 1;

  Map<String, dynamic> toJson() => {
        _versionKey: version.toString(),
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
          driveRevisionsSectionName: {
            _rowsKey: driveRevisions.map((r) => r.toJson()).toList(),
          },
          folderRevisionsSectionName: {
            _rowsKey: folderRevisions.map((r) => r.toJson()).toList(),
          },
          fileRevisionsSectionName: {
            _rowsKey: fileRevisions.map((r) => r.toJson()).toList(),
          },
          licensesSectionName: {
            _rowsKey: licenses.map((l) => l.toJson()).toList(),
          },
        },
      };

  /// The exact inverse of [toJson].
  ///
  /// Extensibility here is deliberately **asymmetric**, and the asymmetry is
  /// the point (§6):
  ///
  ///  * a section this build does not know is **ignored**, so a producer can
  ///    add an optional one without stranding older clients;
  ///  * a section this build *does* know and the payload omits is
  ///    **rejected**, because a reader cannot tell an absent section from an
  ///    empty one, and the two mean opposite things.
  ///
  /// The second half is not hypothetical. Before revisions travelled, this
  /// payload had three sections and the same version number. A producer built
  /// from that commit would sign a payload that verifies, carries a correct
  /// `Entity-Count`, claims honest coverage — and imports into a drive whose
  /// file list renders **empty**, because the file rows are joined through
  /// revisions that were never there. Every check would pass and the user
  /// would lose their drive's contents on screen with nothing logged.
  ///
  /// So: a known section must be present, even if its rows array is empty.
  /// [toJson] always writes all of them, so this costs a correct producer
  /// nothing. A future version that adds a *load-bearing* section raises the
  /// **major** of [DriveStateFormatVersion.current] instead, which the version
  /// check below turns into a clean refusal by older readers.
  ///
  /// ## The version check, and why it has three arms
  ///
  /// [DriveStateFormatVersion] carries the argument for `major.minor`; this is
  /// what it costs here.
  ///
  ///  * **unparseable** — absent, empty, `"1"`, `"1.0.0"`, `"x.y"` — is
  ///    [DriveStateFormatError.malformed]. A version that cannot be compared
  ///    establishes nothing about whether this build could have read the
  ///    payload, so it must not be reported as though it had.
  ///  * **a higher major** is the ordinary forward-compatibility case: an
  ///    older client meeting a newer artifact, expected and not a defect.
  ///  * **a lower major** is refused here, explicitly, rather than left to
  ///    the checks below. Without this arm what happens to it depends on the
  ///    payload's *shape* rather than on its version, which is the whole
  ///    problem: one that genuinely lacks a section fails saying *"payload is
  ///    missing the file_revisions section"*, sending a reader hunting for a
  ///    truncated payload instead of an obsolete one — and one that is
  ///    structurally compatible by accident is **accepted**, under a format
  ///    this build never agreed to read. §6.1 is a whole section about a
  ///    version number that let two different shapes look like the same
  ///    format; this is the same mistake read from the other end.
  factory DriveStateExport.fromJson(Map<String, dynamic> json) {
    final declaredVersion = json[_versionKey];
    if (declaredVersion is! String) {
      throw const DriveStateFormatException(
        DriveStateFormatError.malformed,
        'payload has no string "$_versionKey"',
      );
    }

    final version = DriveStateFormatVersion.tryParse(declaredVersion);
    if (version == null) {
      throw DriveStateFormatException(
        DriveStateFormatError.malformed,
        'payload declares "$_versionKey": "$declaredVersion", which is not a '
        'major.minor format version',
      );
    }
    if (version.isNewerThanThisBuild) {
      throw DriveStateFormatException(
        DriveStateFormatError.unsupportedVersion,
        'the payload is written under format $version and this build reads '
        '${DriveStateFormatVersion.current.major}.x: the artifact is newer '
        'than this client',
      );
    }
    if (version.isOlderThanThisBuild) {
      throw DriveStateFormatException(
        DriveStateFormatError.unsupportedVersion,
        'the payload is written under format $version and this build reads '
        '${DriveStateFormatVersion.current.major}.x: the artifact predates a '
        'breaking change to the format',
      );
    }

    final sections = _asMap(json[_sectionsKey], _sectionsKey);

    final missing = driveStateSectionNames
        .where((name) => !sections.containsKey(name))
        .toList();
    if (missing.isNotEmpty) {
      throw DriveStateFormatException(
        DriveStateFormatError.malformed,
        'payload is missing the ${missing.join(', ')} '
        'section${missing.length == 1 ? '' : 's'}',
      );
    }

    final driveRows = _rowsOf(sections, driveSectionName);
    if (driveRows.length != 1) {
      throw DriveStateFormatException(
        DriveStateFormatError.malformed,
        'the "$driveSectionName" section holds ${driveRows.length} rows, '
        'expected exactly one',
      );
    }

    return DriveStateExport(
      version: version,
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
      driveRevisions: _rowsOf(sections, driveRevisionsSectionName)
          .map(ExportedDriveRevision.fromJson)
          .toList(),
      folderRevisions: _rowsOf(sections, folderRevisionsSectionName)
          .map(ExportedFolderRevision.fromJson)
          .toList(),
      fileRevisions: _rowsOf(sections, fileRevisionsSectionName)
          .map(ExportedFileRevision.fromJson)
          .toList(),
      licenses: _rowsOf(sections, licensesSectionName)
          .map(ExportedLicense.fromJson)
          .toList(),
    );
  }

  @override
  List<Object?> get props => [
        drive,
        folders,
        files,
        driveRevisions,
        folderRevisions,
        fileRevisions,
        licenses,
        coverage,
        version,
      ];
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
    final driveRevisionRows =
        await driveStateDriveRevisionsQuery(driveDao, driveId).get();
    final folderRevisionRows =
        await driveStateFolderRevisionsQuery(driveDao, driveId).get();
    final fileRevisionRows =
        await driveStateFileRevisionsQuery(driveDao, driveId).get();
    final licenseRows = await driveStateLicensesQuery(driveDao, driveId).get();

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
      driveRevisions: driveRevisionRows
          .map((row) =>
              ExportedDriveRevision._fromRow(row, driveDao.driveRevisions))
          .toList(),
      folderRevisions: folderRevisionRows
          .map((row) =>
              ExportedFolderRevision._fromRow(row, driveDao.folderRevisions))
          .toList(),
      fileRevisions: fileRevisionRows
          .map((row) =>
              ExportedFileRevision._fromRow(row, driveDao.fileRevisions))
          .toList(),
      licenses: licenseRows
          .map((row) => ExportedLicense._fromRow(row, driveDao.licenses))
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

/// The drive's `drive_revisions` rows, ordered by their primary key.
///
/// The whole table for this drive, not the newest row: the drive's own history
/// is what the activity view reads, and there is at most a handful of them.
///
/// Its primary key is `(driveId, dateCreated)` and `driveId` is fixed by the
/// where clause, so ordering by `dateCreated` alone is a total order over the
/// result - which is what the byte-identical guarantee needs.
JoinedSelectStatement driveStateDriveRevisionsQuery(
  DriveDao driveDao,
  String driveId,
) {
  final revisions = driveDao.driveRevisions;
  return driveDao.selectOnly(revisions)
    ..addColumns(driveStateExportedColumns(revisions))
    ..where(revisions.driveId.equals(driveId))
    ..orderBy([OrderingTerm.asc(revisions.dateCreated)]);
}

/// The drive's `folder_revisions` rows, ordered by their primary key.
///
/// No `cameFromChain` filter, and none is needed: a revision *is* the thing
/// that filter tests for. The set of folder ids here and the set of folder
/// entries [driveStateFolderEntriesQuery] returns are the same set by
/// construction - the stand-in rows sync and `DriveDao` invent have no
/// revision to carry.
JoinedSelectStatement driveStateFolderRevisionsQuery(
  DriveDao driveDao,
  String driveId,
) {
  final revisions = driveDao.folderRevisions;
  return driveDao.selectOnly(revisions)
    ..addColumns(driveStateExportedColumns(revisions))
    ..where(revisions.driveId.equals(driveId))
    ..orderBy([
      OrderingTerm.asc(revisions.folderId),
      OrderingTerm.asc(revisions.dateCreated),
    ]);
}

/// The drive's `file_revisions` rows, ordered by their primary key.
///
/// Every revision, oldest first within each file. The newest is what the file
/// list resolves its transactions from; the rest are the version history the
/// file details panel shows.
JoinedSelectStatement driveStateFileRevisionsQuery(
  DriveDao driveDao,
  String driveId,
) {
  final revisions = driveDao.fileRevisions;
  return driveDao.selectOnly(revisions)
    ..addColumns(driveStateExportedColumns(revisions))
    ..where(revisions.driveId.equals(driveId))
    ..orderBy([
      OrderingTerm.asc(revisions.fileId),
      OrderingTerm.asc(revisions.dateCreated),
    ]);
}

/// The drive's `licenses` rows, ordered by their primary key.
///
/// Filtered to licences whose file has a revision, which is the same rule
/// every other section obeys: nothing travels that no revision vouches for. A
/// licence attached to a file that is not in the payload is a row about
/// nothing - the file itself would have been filtered out by
/// [_fileEntryCameFromChain] - so this drops exactly the rows a consumer could
/// not use.
JoinedSelectStatement driveStateLicensesQuery(
  DriveDao driveDao,
  String driveId,
) {
  final licenses = driveDao.licenses;
  return driveDao.selectOnly(licenses)
    ..addColumns(driveStateExportedColumns(licenses))
    ..where(
        licenses.driveId.equals(driveId) & _licenseFileCameFromChain(driveDao))
    ..orderBy([
      OrderingTerm.asc(licenses.fileId),
      OrderingTerm.asc(licenses.dataTxId),
      OrderingTerm.asc(licenses.licenseTxId),
    ]);
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
///
/// The cost of dropping them is paid on the other side, on purpose. A ghost's
/// *files* have revisions and so do travel, which leaves the payload naming a
/// parent it does not carry; `DriveStateImporter` closes that graph by
/// materialising the stand-in locally (`_ghostFolderStandIn`), where a
/// fabricated row stays this client's own guess instead of becoming every
/// importer's.
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

/// The same discriminator applied to a `licenses` row, through the file it is
/// attached to.
Expression<bool> _licenseFileCameFromChain(DriveDao driveDao) {
  final licenses = driveDao.licenses;
  final revisions = driveDao.fileRevisions;

  return existsQuery(
    driveDao.selectOnly(revisions)
      ..addColumns([revisions.fileId])
      ..where(revisions.fileId.equalsExp(licenses.fileId) &
          revisions.driveId.equalsExp(licenses.driveId)),
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
///
/// `network_transactions` is the one the file list genuinely needs, and it is
/// still not here. It stays off the wire for the reason above - no `driveId`,
/// so no way to publish this drive's rows without publishing every drive's -
/// and the importer regenerates it from the revisions instead, through the
/// same helpers sync derives it with.
const List<String> _exportedTableNames = [
  driveSectionName,
  folderEntriesSectionName,
  fileEntriesSectionName,
  driveRevisionsSectionName,
  folderRevisionsSectionName,
  fileRevisionsSectionName,
  licensesSectionName,
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
/// of falling off the end of it: `profiles`, `network_transactions` and every
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
    if (table is DriveRevisions) {
      return (
        exported: _exportedDriveRevisionColumns(table),
        withheld: const [],
      );
    }
    if (table is FolderRevisions) {
      return (
        exported: _exportedFolderRevisionColumns(table),
        withheld: const [],
      );
    }
    if (table is FileRevisions) {
      return (
        exported: _exportedFileRevisionColumns(table),
        withheld: const [],
      );
    }
    if (table is Licenses) {
      return (exported: _exportedLicenseColumns(table), withheld: const []);
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

/// `drive_revisions` in full — nothing is withheld, and here is the check.
///
/// The three classes of column that must not travel are key material, anything
/// a key can be derived from, and anything meaningful only to the endpoint
/// that issued it. This table has none: it is the drive's metadata as it stood
/// at each revision (`rootFolderId`, `ownerAddress`, `name`, `privacy`,
/// `bundledIn`, the custom metadata blobs, `isHidden`), plus `metadataTxId`,
/// which is a public Arweave transaction id, plus the `action` and
/// `dateCreated` that order the history.
///
/// Note the absence, rather than the withholding, of the three columns
/// `drives` guards: `encryptedKey`, `driveKeyGenerated` and `keyEncryptionIv`
/// are local key storage, not revision facts, and the revision tables have
/// never had them. There is no `syncCursor` or `lastBlockHeight` here either,
/// for the same reason.
List<GeneratedColumn> _exportedDriveRevisionColumns(DriveRevisions t) => [
      t.driveId,
      t.rootFolderId,
      t.ownerAddress,
      t.name,
      t.privacy,
      t.metadataTxId,
      t.dateCreated,
      t.action,
      t.bundledIn,
      t.customJsonMetadata,
      t.customGQLTags,
      t.isHidden,
    ];

/// `folder_revisions` in full, for the same reasons: entity metadata, one
/// public transaction id, and the ordering columns.
List<GeneratedColumn> _exportedFolderRevisionColumns(FolderRevisions t) => [
      t.folderId,
      t.driveId,
      t.name,
      t.parentFolderId,
      t.metadataTxId,
      t.dateCreated,
      t.action,
      t.customJsonMetadata,
      t.customGQLTags,
      t.isHidden,
    ];

/// `file_revisions` in full.
///
/// Column for column this is `file_entries` plus `metadataTxId`, `action` and
/// the licence pointer, and every one of the shared columns is already
/// published by [_exportedFileEntryColumns] - so a column withheld here but
/// exported there would protect nothing.
///
/// The three that deserve a sentence each, because they name people or places
/// rather than the file:
///
///  * `pinnedDataOwnerAddress` and `originalOwner` are the wallet addresses of
///    *other* people, on data this drive pinned or imported. Public by
///    construction - they are read off the chain - and the file cannot be
///    resolved without them: `_buildPinnedDataTxOwnerOverrides` scopes the
///    confirmation query by exactly this address.
///  * `importSource` records where an imported file came from. Already on the
///    entry row, and the same value.
///
/// `dataTxId` and `metadataTxId` are the point of the section.
List<GeneratedColumn> _exportedFileRevisionColumns(FileRevisions t) => [
      t.fileId,
      t.driveId,
      t.name,
      t.parentFolderId,
      t.size,
      t.lastModifiedDate,
      t.dataContentType,
      t.metadataTxId,
      t.dataTxId,
      t.licenseTxId,
      t.thumbnail,
      t.bundledIn,
      t.dateCreated,
      t.customJsonMetadata,
      t.customGQLTags,
      t.action,
      t.pinnedDataOwnerAddress,
      t.isHidden,
      t.assignedNames,
      t.fallbackTxId,
      t.originalOwner,
      t.importSource,
    ];

/// `licenses` in full: two public transaction ids, the licence's type and
/// shape, the file it is attached to, and `dateCreated`. A licence is a public
/// declaration about what others may do with the data - there is nothing in
/// the row that is not already on chain in the licence transaction itself.
List<GeneratedColumn> _exportedLicenseColumns(Licenses t) => [
      t.fileId,
      t.driveId,
      t.dataTxId,
      t.licenseTxType,
      t.licenseTxId,
      t.bundledIn,
      t.dateCreated,
      t.licenseType,
      t.customGQLTags,
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

/// A `drive_revisions` row.
class ExportedDriveRevision extends Equatable {
  final String driveId;
  final String rootFolderId;
  final String ownerAddress;
  final String name;
  final String privacy;
  final String metadataTxId;
  final DateTime dateCreated;
  final String action;
  final String? bundledIn;
  final String? customJsonMetadata;
  final String? customGQLTags;
  final bool isHidden;

  const ExportedDriveRevision({
    required this.driveId,
    required this.rootFolderId,
    required this.ownerAddress,
    required this.name,
    required this.privacy,
    required this.metadataTxId,
    required this.dateCreated,
    required this.action,
    required this.bundledIn,
    required this.customJsonMetadata,
    required this.customGQLTags,
    required this.isHidden,
  });

  factory ExportedDriveRevision._fromRow(TypedResult row, DriveRevisions t) =>
      ExportedDriveRevision(
        driveId: row.read(t.driveId)!,
        rootFolderId: row.read(t.rootFolderId)!,
        ownerAddress: row.read(t.ownerAddress)!,
        name: row.read(t.name)!,
        privacy: row.read(t.privacy)!,
        metadataTxId: row.read(t.metadataTxId)!,
        dateCreated: row.read(t.dateCreated)!,
        action: row.read(t.action)!,
        bundledIn: row.read(t.bundledIn),
        customJsonMetadata: row.read(t.customJsonMetadata),
        customGQLTags: row.read(t.customGQLTags),
        isHidden: row.read(t.isHidden)!,
      );

  Map<String, dynamic> toJson() => {
        'driveId': driveId,
        'rootFolderId': rootFolderId,
        'ownerAddress': ownerAddress,
        'name': name,
        'privacy': privacy,
        'metadataTxId': metadataTxId,
        'dateCreated': _dateToJson(dateCreated),
        'action': action,
        'bundledIn': bundledIn,
        'customJsonMetadata': customJsonMetadata,
        'customGQLTags': customGQLTags,
        'isHidden': isHidden,
      };

  factory ExportedDriveRevision.fromJson(Map<String, dynamic> json) =>
      ExportedDriveRevision(
        driveId: _required(json, 'driveId'),
        rootFolderId: _required(json, 'rootFolderId'),
        ownerAddress: _required(json, 'ownerAddress'),
        name: _required(json, 'name'),
        privacy: _required(json, 'privacy'),
        metadataTxId: _required(json, 'metadataTxId'),
        dateCreated: _requiredDate(json, 'dateCreated'),
        action: _required(json, 'action'),
        bundledIn: _optional(json, 'bundledIn'),
        customJsonMetadata: _optional(json, 'customJsonMetadata'),
        customGQLTags: _optional(json, 'customGQLTags'),
        isHidden: _required(json, 'isHidden'),
      );

  @override
  List<Object?> get props => [
        driveId,
        rootFolderId,
        ownerAddress,
        name,
        privacy,
        metadataTxId,
        dateCreated,
        action,
        bundledIn,
        customJsonMetadata,
        customGQLTags,
        isHidden,
      ];
}

/// A `folder_revisions` row.
class ExportedFolderRevision extends Equatable {
  final String folderId;
  final String driveId;
  final String name;
  final String? parentFolderId;
  final String metadataTxId;
  final DateTime dateCreated;
  final String action;
  final String? customJsonMetadata;
  final String? customGQLTags;
  final bool isHidden;

  const ExportedFolderRevision({
    required this.folderId,
    required this.driveId,
    required this.name,
    required this.parentFolderId,
    required this.metadataTxId,
    required this.dateCreated,
    required this.action,
    required this.customJsonMetadata,
    required this.customGQLTags,
    required this.isHidden,
  });

  factory ExportedFolderRevision._fromRow(TypedResult row, FolderRevisions t) =>
      ExportedFolderRevision(
        folderId: row.read(t.folderId)!,
        driveId: row.read(t.driveId)!,
        name: row.read(t.name)!,
        parentFolderId: row.read(t.parentFolderId),
        metadataTxId: row.read(t.metadataTxId)!,
        dateCreated: row.read(t.dateCreated)!,
        action: row.read(t.action)!,
        customJsonMetadata: row.read(t.customJsonMetadata),
        customGQLTags: row.read(t.customGQLTags),
        isHidden: row.read(t.isHidden)!,
      );

  Map<String, dynamic> toJson() => {
        'folderId': folderId,
        'driveId': driveId,
        'name': name,
        'parentFolderId': parentFolderId,
        'metadataTxId': metadataTxId,
        'dateCreated': _dateToJson(dateCreated),
        'action': action,
        'customJsonMetadata': customJsonMetadata,
        'customGQLTags': customGQLTags,
        'isHidden': isHidden,
      };

  factory ExportedFolderRevision.fromJson(Map<String, dynamic> json) =>
      ExportedFolderRevision(
        folderId: _required(json, 'folderId'),
        driveId: _required(json, 'driveId'),
        name: _required(json, 'name'),
        parentFolderId: _optional(json, 'parentFolderId'),
        metadataTxId: _required(json, 'metadataTxId'),
        dateCreated: _requiredDate(json, 'dateCreated'),
        action: _required(json, 'action'),
        customJsonMetadata: _optional(json, 'customJsonMetadata'),
        customGQLTags: _optional(json, 'customGQLTags'),
        isHidden: _required(json, 'isHidden'),
      );

  @override
  List<Object?> get props => [
        folderId,
        driveId,
        name,
        parentFolderId,
        metadataTxId,
        dateCreated,
        action,
        customJsonMetadata,
        customGQLTags,
        isHidden,
      ];
}

/// A `file_revisions` row — the one the file list cannot render without.
class ExportedFileRevision extends Equatable {
  final String fileId;
  final String driveId;
  final String name;
  final String parentFolderId;
  final int size;
  final DateTime lastModifiedDate;
  final String? dataContentType;
  final String metadataTxId;
  final String dataTxId;
  final String? licenseTxId;
  final String? thumbnail;
  final String? bundledIn;
  final DateTime dateCreated;
  final String? customJsonMetadata;
  final String? customGQLTags;
  final String action;
  final String? pinnedDataOwnerAddress;
  final bool isHidden;
  final String? assignedNames;
  final String? fallbackTxId;
  final String? originalOwner;
  final String? importSource;

  const ExportedFileRevision({
    required this.fileId,
    required this.driveId,
    required this.name,
    required this.parentFolderId,
    required this.size,
    required this.lastModifiedDate,
    required this.dataContentType,
    required this.metadataTxId,
    required this.dataTxId,
    required this.licenseTxId,
    required this.thumbnail,
    required this.bundledIn,
    required this.dateCreated,
    required this.customJsonMetadata,
    required this.customGQLTags,
    required this.action,
    required this.pinnedDataOwnerAddress,
    required this.isHidden,
    required this.assignedNames,
    required this.fallbackTxId,
    required this.originalOwner,
    required this.importSource,
  });

  factory ExportedFileRevision._fromRow(TypedResult row, FileRevisions t) =>
      ExportedFileRevision(
        fileId: row.read(t.fileId)!,
        driveId: row.read(t.driveId)!,
        name: row.read(t.name)!,
        parentFolderId: row.read(t.parentFolderId)!,
        size: row.read(t.size)!,
        lastModifiedDate: row.read(t.lastModifiedDate)!,
        dataContentType: row.read(t.dataContentType),
        metadataTxId: row.read(t.metadataTxId)!,
        dataTxId: row.read(t.dataTxId)!,
        licenseTxId: row.read(t.licenseTxId),
        thumbnail: row.read(t.thumbnail),
        bundledIn: row.read(t.bundledIn),
        dateCreated: row.read(t.dateCreated)!,
        customJsonMetadata: row.read(t.customJsonMetadata),
        customGQLTags: row.read(t.customGQLTags),
        action: row.read(t.action)!,
        pinnedDataOwnerAddress: row.read(t.pinnedDataOwnerAddress),
        isHidden: row.read(t.isHidden)!,
        assignedNames: row.read(t.assignedNames),
        fallbackTxId: row.read(t.fallbackTxId),
        originalOwner: row.read(t.originalOwner),
        importSource: row.read(t.importSource),
      );

  Map<String, dynamic> toJson() => {
        'fileId': fileId,
        'driveId': driveId,
        'name': name,
        'parentFolderId': parentFolderId,
        'size': size,
        'lastModifiedDate': _dateToJson(lastModifiedDate),
        'dataContentType': dataContentType,
        'metadataTxId': metadataTxId,
        'dataTxId': dataTxId,
        'licenseTxId': licenseTxId,
        'thumbnail': thumbnail,
        'bundledIn': bundledIn,
        'dateCreated': _dateToJson(dateCreated),
        'customJsonMetadata': customJsonMetadata,
        'customGQLTags': customGQLTags,
        'action': action,
        'pinnedDataOwnerAddress': pinnedDataOwnerAddress,
        'isHidden': isHidden,
        'assignedNames': assignedNames,
        'fallbackTxId': fallbackTxId,
        'originalOwner': originalOwner,
        'importSource': importSource,
      };

  factory ExportedFileRevision.fromJson(Map<String, dynamic> json) =>
      ExportedFileRevision(
        fileId: _required(json, 'fileId'),
        driveId: _required(json, 'driveId'),
        name: _required(json, 'name'),
        parentFolderId: _required(json, 'parentFolderId'),
        size: _required(json, 'size'),
        lastModifiedDate: _requiredDate(json, 'lastModifiedDate'),
        dataContentType: _optional(json, 'dataContentType'),
        metadataTxId: _required(json, 'metadataTxId'),
        dataTxId: _required(json, 'dataTxId'),
        licenseTxId: _optional(json, 'licenseTxId'),
        thumbnail: _optional(json, 'thumbnail'),
        bundledIn: _optional(json, 'bundledIn'),
        dateCreated: _requiredDate(json, 'dateCreated'),
        customJsonMetadata: _optional(json, 'customJsonMetadata'),
        customGQLTags: _optional(json, 'customGQLTags'),
        action: _required(json, 'action'),
        pinnedDataOwnerAddress: _optional(json, 'pinnedDataOwnerAddress'),
        isHidden: _required(json, 'isHidden'),
        assignedNames: _optional(json, 'assignedNames'),
        fallbackTxId: _optional(json, 'fallbackTxId'),
        originalOwner: _optional(json, 'originalOwner'),
        importSource: _optional(json, 'importSource'),
      );

  @override
  List<Object?> get props => [
        fileId,
        driveId,
        name,
        parentFolderId,
        size,
        lastModifiedDate,
        dataContentType,
        metadataTxId,
        dataTxId,
        licenseTxId,
        thumbnail,
        bundledIn,
        dateCreated,
        customJsonMetadata,
        customGQLTags,
        action,
        pinnedDataOwnerAddress,
        isHidden,
        assignedNames,
        fallbackTxId,
        originalOwner,
        importSource,
      ];
}

/// A `licenses` row.
class ExportedLicense extends Equatable {
  final String fileId;
  final String driveId;
  final String dataTxId;
  final String licenseTxType;
  final String licenseTxId;
  final String? bundledIn;
  final DateTime dateCreated;
  final String licenseType;
  final String? customGQLTags;

  const ExportedLicense({
    required this.fileId,
    required this.driveId,
    required this.dataTxId,
    required this.licenseTxType,
    required this.licenseTxId,
    required this.bundledIn,
    required this.dateCreated,
    required this.licenseType,
    required this.customGQLTags,
  });

  factory ExportedLicense._fromRow(TypedResult row, Licenses t) =>
      ExportedLicense(
        fileId: row.read(t.fileId)!,
        driveId: row.read(t.driveId)!,
        dataTxId: row.read(t.dataTxId)!,
        licenseTxType: row.read(t.licenseTxType)!,
        licenseTxId: row.read(t.licenseTxId)!,
        bundledIn: row.read(t.bundledIn),
        dateCreated: row.read(t.dateCreated)!,
        licenseType: row.read(t.licenseType)!,
        customGQLTags: row.read(t.customGQLTags),
      );

  Map<String, dynamic> toJson() => {
        'fileId': fileId,
        'driveId': driveId,
        'dataTxId': dataTxId,
        'licenseTxType': licenseTxType,
        'licenseTxId': licenseTxId,
        'bundledIn': bundledIn,
        'dateCreated': _dateToJson(dateCreated),
        'licenseType': licenseType,
        'customGQLTags': customGQLTags,
      };

  factory ExportedLicense.fromJson(Map<String, dynamic> json) =>
      ExportedLicense(
        fileId: _required(json, 'fileId'),
        driveId: _required(json, 'driveId'),
        dataTxId: _required(json, 'dataTxId'),
        licenseTxType: _required(json, 'licenseTxType'),
        licenseTxId: _required(json, 'licenseTxId'),
        bundledIn: _optional(json, 'bundledIn'),
        dateCreated: _requiredDate(json, 'dateCreated'),
        licenseType: _required(json, 'licenseType'),
        customGQLTags: _optional(json, 'customGQLTags'),
      );

  @override
  List<Object?> get props => [
        fileId,
        driveId,
        dataTxId,
        licenseTxType,
        licenseTxId,
        bundledIn,
        dateCreated,
        licenseType,
        customGQLTags,
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
