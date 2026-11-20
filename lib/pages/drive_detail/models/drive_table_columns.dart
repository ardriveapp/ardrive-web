import 'package:ardrive/models/enums.dart';
import 'package:ardrive/services/license/license_state.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/utils/compare_alphabetically_and_natural.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:path/path.dart' as path;

/// The explorer table's columns, by the number the reader's saved choice of
/// which to show is keyed on (`drive_detail_column_<index>`).
///
/// Only ever append: a number that moved would turn a saved choice about one
/// column into a choice about another. The order the columns are listed in
/// the table has to follow these numbers too.
class ColumnIndexes {
  static const int name = 0;
  static const int size = 1;
  static const int lastUpdated = 2;
  static const int dateCreated = 3;
  static const int licenseType = 4;
  static const int type = 5;
  static const int transactionId = 6;
  static const int status = 7;

  /// How many columns there are: saved choices are read for each.
  static const int count = 8;

  /// Whether a column is shown when the reader never chose, other than
  /// License, whose default depends on the drive.
  /// Type is not: the icon and the name's extension already say it.
  static bool shownByDefault(int index) =>
      index != licenseType &&
      index != type &&
      index != transactionId &&
      index != status;
}

/// Whether the Type, Transaction ID or Status column is shown: the layout has
/// to be wide enough, and then it is the reader's choice, or its default when
/// there is none. All three are opt-in.
bool showsAddedColumn({
  required int index,
  required double width,
  required Map<int, bool> columnVisibility,
}) =>
    width > typeColumnsMinWidth &&
    (columnVisibility[index] ?? ColumnIndexes.shownByDefault(index));

/// Widest layout that drops the Type, Transaction ID and Status columns.
/// Past License's 820, so they go before it as the table narrows.
const double typeColumnsMinWidth = 900;

/// What a file is, for the Type column: a [kind], and the [detail] the kind
/// is spoken with, such as the format of an image.
class DriveTableType {
  const DriveTableType(this.kind, [this.detail]);

  final DriveTableTypeKind kind;
  final String? detail;

  @override
  bool operator ==(Object other) =>
      other is DriveTableType && other.kind == kind && other.detail == detail;

  @override
  int get hashCode => Object.hash(kind, detail);

  @override
  String toString() => 'DriveTableType($kind, $detail)';
}

enum DriveTableTypeKind {
  folder,

  /// A format named the same in every language: PDF, HTML, JSON. The detail.
  named,

  /// Plain text.
  text,

  /// An Arweave manifest, which the app calls a deployment.
  deployment,

  /// An image, video, audio file or archive; the detail is its format.
  image,
  video,
  audio,
  archive,

  /// Not known: the detail is its extension, if it has one.
  other,
}

const _imageFormats = {
  'png': 'PNG',
  'jpeg': 'JPEG',
  'jpg': 'JPEG',
  'gif': 'GIF',
  'svg+xml': 'SVG',
  'webp': 'WebP',
  'avif': 'AVIF',
  'bmp': 'BMP',
  'tiff': 'TIFF',
  'heic': 'HEIC',
  'x-icon': 'ICO',
  'vnd.microsoft.icon': 'ICO',
};

const _videoFormats = {
  'mp4': 'MP4',
  'webm': 'WebM',
  'quicktime': 'MOV',
  'x-matroska': 'MKV',
  'mpeg': 'MPEG',
  'ogg': 'OGG',
  'x-msvideo': 'AVI',
};

const _audioFormats = {
  'mpeg': 'MP3',
  'mp3': 'MP3',
  'wav': 'WAV',
  'x-wav': 'WAV',
  'wave': 'WAV',
  'ogg': 'OGG',
  'flac': 'FLAC',
  'x-flac': 'FLAC',
  'aac': 'AAC',
  'mp4': 'M4A',
  'x-m4a': 'M4A',
  'webm': 'WebM',
};

const _archiveFormats = {
  'application/zip': 'ZIP',
  'application/x-rar-compressed': 'RAR',
  'application/vnd.rar': 'RAR',
  'application/x-7z-compressed': '7Z',
  'application/gzip': 'GZIP',
  'application/x-gzip': 'GZIP',
  'application/x-tar': 'TAR',
};

const _namedFormats = {
  'application/pdf': 'PDF',
  'text/html': 'HTML',
  'application/xhtml+xml': 'HTML',
  'text/css': 'CSS',
  'text/csv': 'CSV',
  'text/javascript': 'JavaScript',
  'application/javascript': 'JavaScript',
  'text/markdown': 'Markdown',
  'text/x-markdown': 'Markdown',
  'application/xml': 'XML',
  'text/xml': 'XML',
};

final _extension = RegExp(r'^[a-z0-9]{1,8}$', caseSensitive: false);

/// What to call a row in the Type column, from its content type and name.
///
/// A folder, then the kinds worth a word of their own, then the file
/// extension for anything else, and nothing more when there is none. Pure,
/// so the labels can be checked without a table.
DriveTableType driveTableType({
  required String contentType,
  required String name,
}) {
  // Without parameters: `text/plain; charset=utf-8` is `text/plain`.
  final media = contentType.split(';').first.trim().toLowerCase();

  if (media == 'folder') return const DriveTableType(DriveTableTypeKind.folder);

  if (FileTypeHelper.isManifest(media)) {
    return const DriveTableType(DriveTableTypeKind.deployment);
  }
  if (FileTypeHelper.isJson(media)) {
    return const DriveTableType(DriveTableTypeKind.named, 'JSON');
  }

  final named = _namedFormats[media];
  if (named != null) return DriveTableType(DriveTableTypeKind.named, named);

  final archive = _archiveFormats[media];
  if (archive != null) {
    return DriveTableType(DriveTableTypeKind.archive, archive);
  }

  final slash = media.indexOf('/');
  if (slash > 0) {
    final family = media.substring(0, slash);
    final subtype = media.substring(slash + 1);
    final formats = switch (family) {
      'image' => _imageFormats,
      'video' => _videoFormats,
      'audio' => _audioFormats,
      _ => null,
    };
    final format = formats?[subtype];
    if (format != null) {
      return DriveTableType(
        switch (family) {
          'image' => DriveTableTypeKind.image,
          'video' => DriveTableTypeKind.video,
          _ => DriveTableTypeKind.audio,
        },
        format,
      );
    }
    if (family == 'text') return const DriveTableType(DriveTableTypeKind.text);
  }

  final extension = path.extension(name).replaceFirst('.', '');
  return DriveTableType(
    DriveTableTypeKind.other,
    _extension.hasMatch(extension) ? extension.toUpperCase() : null,
  );
}

/// [type] in the reader's language.
String driveTableTypeLabel(AppLocalizations l10n, DriveTableType type) {
  final detail = type.detail;
  switch (type.kind) {
    case DriveTableTypeKind.folder:
      return l10n.typeFolder;
    case DriveTableTypeKind.named:
      return detail!;
    case DriveTableTypeKind.text:
      return l10n.typeText;
    case DriveTableTypeKind.deployment:
      return l10n.typeDeployment;
    case DriveTableTypeKind.image:
      return l10n.typeImage(detail!);
    case DriveTableTypeKind.video:
      return l10n.typeVideo(detail!);
    case DriveTableTypeKind.audio:
      return l10n.typeAudio(detail!);
    case DriveTableTypeKind.archive:
      return l10n.typeArchive(detail!);
    case DriveTableTypeKind.other:
      return detail == null
          ? l10n.typeFile
          : l10n.typeFileWithExtension(detail);
  }
}

/// What the Status column says of a row: [TransactionStatus] as a word, or
/// null when the row has no status to give (a folder).
String? driveTableStatusLabel(AppLocalizations l10n, String? status) {
  switch (status) {
    case TransactionStatus.pending:
      return l10n.fileStatusPending;
    case TransactionStatus.confirmed:
      return l10n.fileStatusPermanent;
    case TransactionStatus.failed:
      return l10n.fileStatusFailed;
    default:
      return null;
  }
}

/// Failed first, since it is what needs looking at, then pending, then
/// permanent. A row with no status goes last.
int driveTableStatusRank(String? status) {
  switch (status) {
    case TransactionStatus.failed:
      return 0;
    case TransactionStatus.pending:
      return 1;
    case TransactionStatus.confirmed:
      return 2;
    default:
      return 3;
  }
}

/// A row's data transaction, which a folder has none of.
String? driveTableTransactionId(ArDriveDataTableItem item) =>
    item is FileDataTableItem ? item.dataTxId : null;

/// Sorts folders and files, each on its own, by the column at [columnIndex].
/// The caller puts the folders first.
///
/// [typeLabel] is a row's Type as the reader reads it, which is what that
/// column sorts on.
void sortDriveTableItems(
  List<ArDriveDataTableItem> folders,
  List<ArDriveDataTableItem> files,
  int columnIndex,
  TableSort ascDescSort, {
  required String Function(ArDriveDataTableItem) typeLabel,
}) {
  _sortItems(folders, columnIndex, ascDescSort, typeLabel);
  _sortItems(files, columnIndex, ascDescSort, typeLabel);
}

/// The explorer's rows in the order the column at [columnIndex] puts them:
/// folders first, then files, each sorted on its own. The list's header sort
/// and the gallery both use this, so a folder reads in the same order in
/// either.
List<ArDriveDataTableItem> sortExplorerRows(
  List<ArDriveDataTableItem> rows,
  int columnIndex,
  TableSort order, {
  required String Function(ArDriveDataTableItem) typeLabel,
}) {
  final folders = <ArDriveDataTableItem>[];
  final files = <ArDriveDataTableItem>[];
  for (final row in rows) {
    (row is FolderDataTableItem ? folders : files).add(row);
  }
  sortDriveTableItems(folders, files, columnIndex, order, typeLabel: typeLabel);
  return folders + files;
}

int _getResult(int result, TableSort ascDescSort) {
  if (ascDescSort == TableSort.asc) {
    result *= -1;
  }

  return result;
}

void _sortItems(
  List<ArDriveDataTableItem> items,
  int columnIndex,
  TableSort ascDescSort,
  String Function(ArDriveDataTableItem) typeLabel,
) {
  if (columnIndex == ColumnIndexes.licenseType) {
    final licenseFiles = items.where((e) => e.licenseType != null).toList();

    licenseFiles.sort((a, b) {
      int result = 0;
      result = (a.licenseType ?? LicenseType.unknown)
          .index
          .compareTo((b.licenseType ?? LicenseType.unknown).index);
      return _getResult(result, ascDescSort);
    });

    final noLicenseFiles = items.where((e) => e.licenseType == null).toList();

    noLicenseFiles.sort((a, b) {
      int result = 0;
      result = compareAlphabeticallyAndNatural(a.name, b.name);
      return _getResult(result, ascDescSort);
    });
    items.clear();
    items.addAll(licenseFiles + noLicenseFiles);
    return;
  }

  // Labels read once per row, not once per comparison.
  final labels = columnIndex == ColumnIndexes.type
      ? {for (final item in items) item: typeLabel(item)}
      : null;

  items.sort((a, b) {
    int result = 0;
    if (columnIndex == ColumnIndexes.name) {
      result = compareAlphabeticallyAndNatural(a.name, b.name);
    } else if (columnIndex == ColumnIndexes.size) {
      result = (a.size ?? 0).compareTo(b.size ?? 0);
    } else if (columnIndex == ColumnIndexes.lastUpdated) {
      result = a.lastUpdated.compareTo(b.lastUpdated);
    } else if (columnIndex == ColumnIndexes.type) {
      result = compareAlphabeticallyAndNatural(labels![a]!, labels[b]!);
      if (result == 0) {
        result = compareAlphabeticallyAndNatural(a.name, b.name);
      }
    } else if (columnIndex == ColumnIndexes.transactionId) {
      // The whole ID, not the short form on screen. A row with none goes
      // with the empty string.
      result = (driveTableTransactionId(a) ?? '')
          .compareTo(driveTableTransactionId(b) ?? '');
      // Folders have none: by name, so their order holds between sorts.
      if (result == 0) {
        result = compareAlphabeticallyAndNatural(a.name, b.name);
      }
    } else if (columnIndex == ColumnIndexes.status) {
      result = driveTableStatusRank(a.fileStatusFromTransactions)
          .compareTo(driveTableStatusRank(b.fileStatusFromTransactions));
      if (result == 0) {
        result = compareAlphabeticallyAndNatural(a.name, b.name);
      }
    } else {
      result = a.dateCreated.compareTo(b.dateCreated);
    }
    return _getResult(result, ascDescSort);
  });
}
