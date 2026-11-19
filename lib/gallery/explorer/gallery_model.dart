import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/pages/drive_detail/models/drive_table_columns.dart';
import 'package:ardrive_ui/ardrive_ui.dart' show TableSort;

/// A month of files in the gallery.
class GalleryMonth {
  const GalleryMonth(this.year, this.month, this.items);

  final int year;
  final int month;
  final List<ArDriveDataTableItem> items;

  /// A stable id for the month: `2026-10`.
  String get id => '$year-${month.toString().padLeft(2, '0')}';
}

/// What the gallery shows for a folder: its folders, then its files by month.
class GalleryModel {
  const GalleryModel(this.folders, this.months);

  final List<ArDriveDataTableItem> folders;
  final List<GalleryMonth> months;

  /// Every tile in display order: the order arrow keys, Shift ranges and the
  /// gallery-wide index follow.
  List<ArDriveDataTableItem> get flat => [
        ...folders,
        for (final month in months) ...month.items,
      ];
}

/// The date a file is filed under for [sortColumn]: Last updated sorts and
/// groups by that date; every other column groups by Date created. A sort by
/// name or size still keeps its order inside each month; only the month
/// headers are by date.
DateTime galleryDateOf(ArDriveDataTableItem item, int? sortColumn) =>
    sortColumn == ColumnIndexes.lastUpdated
        ? item.lastUpdated
        : item.dateCreated;

/// Arranges [items] (already the folder's visible rows) as the gallery shows
/// them.
///
/// - The order is the list's: [sortExplorerRows] for the column the reader
///   sorted by in this folder, the folder's own order when they have not, and
///   folders before files either way.
/// - Folders are not grouped.
/// - Files are grouped by month of [galleryDateOf]. Sorted by a date column,
///   months follow the sort, and so do the files in them: whatever order the list's
///   header gives, months and files follow it. Sorted by anything else, months
///   run newest first and the files keep the sort's order inside each month.
GalleryModel buildGalleryModel(
  List<ArDriveDataTableItem> items, {
  required int? sortColumn,
  required TableSort? sortOrder,
  required String Function(ArDriveDataTableItem) typeLabel,
  bool toLocal = true,
}) {
  final List<ArDriveDataTableItem> ordered;
  if (sortColumn != null && sortOrder != null) {
    ordered =
        sortExplorerRows(items, sortColumn, sortOrder, typeLabel: typeLabel);
  } else {
    ordered = [
      ...items.whereType<FolderDataTableItem>(),
      ...items.where((i) => i is! FolderDataTableItem),
    ];
  }

  final folders = <ArDriveDataTableItem>[];
  final byMonth = <String, GalleryMonth>{};
  final appearance = <String>[];
  for (final item in ordered) {
    if (item is FolderDataTableItem) {
      folders.add(item);
      continue;
    }
    final date = galleryDateOf(item, sortColumn);
    final d = toLocal ? date.toLocal() : date;
    final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
    final month = byMonth.putIfAbsent(key, () {
      appearance.add(key);
      return GalleryMonth(d.year, d.month, []);
    });
    month.items.add(item);
  }

  final dateSort = sortColumn == ColumnIndexes.lastUpdated ||
      sortColumn == ColumnIndexes.dateCreated;
  final keys = [...appearance];
  if (!dateSort) {
    // Newest month first; the key sorts as text because it is zero padded.
    keys.sort((a, b) => b.compareTo(a));
  }
  return GalleryModel(folders, [for (final key in keys) byMonth[key]!]);
}
