import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';

/// Which modifier a click carried.
enum GalleryClickKind { plain, range, toggle }

/// What a click on a tile changes, in the explorer's own terms.
///
/// The list's row model, as a pure function so the gallery and its tests do
/// not repeat it:
///
/// - A plain click chooses that one item and ends any multi-selection.
/// - Ctrl or Cmd adds the item to the chosen ones, or takes it out. The
///   item already chosen by a plain click counts as the first.
/// - Shift chooses every item from the anchor (the last one clicked plain or
///   with Ctrl) to this one, in display order.
class GallerySelectionChange {
  const GallerySelectionChange({
    this.select,
    this.selectMany,
    required this.anchor,
  });

  /// Choose just this item: `DriveDetailCubit.selectDataItem`, with the
  /// details panel left as it is.
  final ArDriveDataTableItem? select;

  /// Make these the multi-selection: `DriveDetailCubit.selectItems`. An empty
  /// list ends multi-selection. When [select] is also set, this clears first.
  final List<ArDriveDataTableItem>? selectMany;

  final ArDriveDataTableItem? anchor;
}

GallerySelectionChange resolveGalleryClick({
  required ArDriveDataTableItem item,
  required GalleryClickKind kind,
  required List<ArDriveDataTableItem> ordered,
  required List<ArDriveDataTableItem> multiSelected,
  required ArDriveDataTableItem? selected,
  required ArDriveDataTableItem? anchor,
}) {
  switch (kind) {
    case GalleryClickKind.plain:
      return GallerySelectionChange(
        select: item,
        selectMany: multiSelected.isEmpty ? null : const [],
        anchor: item,
      );
    case GalleryClickKind.toggle:
      final base = multiSelected.isNotEmpty
          ? multiSelected
          : [if (selected != null) selected];
      final has = base.any((e) => e.id == item.id);
      final next =
          has ? base.where((e) => e.id != item.id).toList() : [...base, item];
      return GallerySelectionChange(selectMany: next, anchor: item);
    case GalleryClickKind.range:
      final from = anchor ?? selected ?? item;
      final a = ordered.indexWhere((e) => e.id == from.id);
      final b = ordered.indexWhere((e) => e.id == item.id);
      if (a < 0 || b < 0) {
        return GallerySelectionChange(selectMany: [item], anchor: item);
      }
      final lo = a < b ? a : b;
      final hi = a < b ? b : a;
      return GallerySelectionChange(
        selectMany: ordered.sublist(lo, hi + 1),
        // Shift keeps the anchor, so the next Shift click extends from it.
        anchor: from,
      );
  }
}

/// What selecting a month's control does: the multi-selection afterwards.
///
/// When every item of the month is already chosen it takes them out and keeps
/// the rest; otherwise it adds the whole month to what is chosen.
List<ArDriveDataTableItem> resolveMonthToggle({
  required List<ArDriveDataTableItem> month,
  required List<ArDriveDataTableItem> multiSelected,
}) {
  final chosen = {for (final e in multiSelected) e.id};
  final all = month.every((e) => chosen.contains(e.id));
  if (all) {
    final inMonth = {for (final e in month) e.id};
    return multiSelected.where((e) => !inMonth.contains(e.id)).toList();
  }
  return [
    ...multiSelected,
    ...month.where((e) => !chosen.contains(e.id)),
  ];
}
