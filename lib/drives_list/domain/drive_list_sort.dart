import 'package:ardrive/drives_list/domain/drive_list_item.dart';
import 'package:ardrive/utils/compare_alphabetically_and_natural.dart';

/// Which column the drives list is ordered by.
///
/// Name is the default and the only one that can never be unknown, which is
/// why it is also the tie-breaker for every other column.
enum DriveListSort { name, lastSynced, files, size, created }

/// How a column orders, and what it does with drives that cannot answer it.
///
/// Three of these columns are withheld until a drive has been walked -
/// `fileCount`, `totalSize` and `lastSyncedAt` are null until then, and the
/// row shows a dash rather than a zero. A dash is not a small number and must
/// not sort like one: an unread drive has no value on that column at all, so
/// it sorts to the bottom whichever way the arrow points. Sorting them as zero
/// would fill the top of an ascending list with drives that have never been
/// read, which is the opposite of what asking for the smallest is for.
extension DriveListSortComparator on DriveListSort {
  int Function(DriveListItem, DriveListItem) comparator({
    required bool ascending,
  }) {
    int byName(DriveListItem a, DriveListItem b) =>
        compareAlphabeticallyAndNatural(a.name, b.name);

    /// Applies the direction to a comparison, then falls back to the name so
    /// the order is total - equal file counts must not shuffle between builds.
    int ordered(
      DriveListItem a,
      DriveListItem b,
      int Function(DriveListItem, DriveListItem) compare,
    ) {
      final result = compare(a, b);

      if (result != 0) {
        return ascending ? result : -result;
      }

      return byName(a, b);
    }

    /// Nulls last, both directions, and never compared against a value.
    int? unknownsLast(Object? a, Object? b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;

      return null;
    }

    switch (this) {
      case DriveListSort.name:
        return (a, b) => ascending ? byName(a, b) : -byName(a, b);
      case DriveListSort.created:
        return (a, b) =>
            ordered(a, b, (x, y) => x.dateCreated.compareTo(y.dateCreated));
      case DriveListSort.lastSynced:
        return (a, b) {
          final unknown = unknownsLast(a.lastSyncedAt, b.lastSyncedAt);
          if (unknown != null) return unknown == 0 ? byName(a, b) : unknown;

          return ordered(
            a,
            b,
            (x, y) => x.lastSyncedAt!.compareTo(y.lastSyncedAt!),
          );
        };
      case DriveListSort.files:
        return (a, b) {
          final unknown = unknownsLast(a.fileCount, b.fileCount);
          if (unknown != null) return unknown == 0 ? byName(a, b) : unknown;

          return ordered(a, b, (x, y) => x.fileCount!.compareTo(y.fileCount!));
        };
      case DriveListSort.size:
        return (a, b) {
          final unknown = unknownsLast(a.totalSize, b.totalSize);
          if (unknown != null) return unknown == 0 ? byName(a, b) : unknown;

          return ordered(a, b, (x, y) => x.totalSize!.compareTo(y.totalSize!));
        };
    }
  }
}
