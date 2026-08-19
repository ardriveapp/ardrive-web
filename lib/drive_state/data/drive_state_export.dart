import 'package:ardrive/models/models.dart';
import 'package:drift/drift.dart';
import 'package:equatable/equatable.dart';

/// Exports one drive's current state from the local database, and converts it
/// to and from the artifact's section format.
///
/// Two rules from `docs/DRIVE_STATE_ARTIFACT.md` shape everything here:
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
///    `folder_entries` hold one row per entity; the revision tables are not
///    read. History stays available through snapshots and GraphQL.

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

/// One drive's current state, as an object graph.
class DriveStateExport extends Equatable {
  final ExportedDrive drive;
  final List<ExportedFolderEntry> folders;
  final List<ExportedFileEntry> files;

  const DriveStateExport({
    required this.drive,
    required this.folders,
    required this.files,
  });

  /// The number of entities the payload carries, which the entity's
  /// `Entity-Count` tag declares so that an importer can prove the body meant
  /// what the tags promised (§3.2).
  int get entityCount => folders.length + files.length + 1;

  Map<String, dynamic> toJson() => {
        _versionKey: driveStateFormatVersion,
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
  List<Object?> get props => [drive, folders, files];
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
  final drives = driveDao.drives;
  final driveRow = await (driveDao.selectOnly(drives)
        ..addColumns(driveStateExportedColumns(drives))
        ..where(drives.id.equals(driveId)))
      .getSingleOrNull();

  if (driveRow == null) {
    throw StateError('cannot export drive $driveId: no such drive');
  }

  final folderEntries = driveDao.folderEntries;
  final folderRows = await (driveDao.selectOnly(folderEntries)
        ..addColumns(driveStateExportedColumns(folderEntries))
        ..where(folderEntries.driveId.equals(driveId))
        ..orderBy([OrderingTerm.asc(folderEntries.id)]))
      .get();

  final fileEntries = driveDao.fileEntries;
  final fileRows = await (driveDao.selectOnly(fileEntries)
        ..addColumns(driveStateExportedColumns(fileEntries))
        ..where(fileEntries.driveId.equals(driveId))
        ..orderBy([OrderingTerm.asc(fileEntries.id)]))
      .get();

  return DriveStateExport(
    drive: ExportedDrive._fromRow(driveRow, drives),
    folders: folderRows
        .map((row) => ExportedFolderEntry._fromRow(row, folderEntries))
        .toList(),
    files: fileRows
        .map((row) => ExportedFileEntry._fromRow(row, fileEntries))
        .toList(),
  );
}

/// The columns of [table] the export reads, in wire order.
///
/// Exposed so a test can assert the projection against the live schema. A
/// migration that adds a column to an exported table makes
/// `exported + withheld` disagree with the table's own column list, and the
/// test fails until the new column is deliberately placed in one or the other.
List<GeneratedColumn> driveStateExportedColumns(TableInfo table) {
  if (table is Drives) return _exportedDriveColumns(table);
  if (table is FolderEntries) return _exportedFolderEntryColumns(table);
  if (table is FileEntries) return _exportedFileEntryColumns(table);
  throw ArgumentError('${table.actualTableName} is not an exported table');
}

/// The columns of [table] the export deliberately does not read.
List<GeneratedColumn> driveStateWithheldColumns(TableInfo table) {
  if (table is Drives) return _withheldDriveColumns(table);
  if (table is FolderEntries) return const [];
  if (table is FileEntries) return const [];
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
    ];

List<GeneratedColumn> _exportedDriveColumns(Drives t) => [
      t.id,
      t.rootFolderId,
      t.ownerAddress,
      t.name,
      t.syncCursor,
      t.lastBlockHeight,
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
  final String? syncCursor;
  final int? lastBlockHeight;
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
    required this.syncCursor,
    required this.lastBlockHeight,
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
        syncCursor: row.read(t.syncCursor),
        lastBlockHeight: row.read(t.lastBlockHeight),
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
        'syncCursor': syncCursor,
        'lastBlockHeight': lastBlockHeight,
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
        syncCursor: _optional(json, 'syncCursor'),
        lastBlockHeight: _optional(json, 'lastBlockHeight'),
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
        syncCursor,
        lastBlockHeight,
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
