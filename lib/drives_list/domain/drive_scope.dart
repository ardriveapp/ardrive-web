import 'package:ardrive/drives_list/domain/drive_list_item.dart';

/// Which drives the list is showing.
///
/// These were the sidebar's section headings - PUBLIC DRIVES, PRIVATE DRIVES,
/// SHARED DRIVES - sitting above a second copy of the drive list the main
/// panel was already showing in full, with more detail and columns to explain
/// itself. The headings were the only part carrying navigation; the names under
/// them were duplication.
///
/// So the headings become the navigation and the names stay in the table. The
/// sidebar is then short and fixed-height, and Private stops being something a
/// reader scrolls past fifteen public drives to reach.
enum DriveScope {
  all,
  public,
  private,
  sharedWithMe,
  hidden;

  bool matches(DriveListItem drive) {
    switch (this) {
      case DriveScope.all:
        return !drive.isHidden;
      case DriveScope.public:
        return !drive.isPrivate && !drive.isHidden;
      case DriveScope.private:
        return drive.isPrivate && !drive.isHidden;
      case DriveScope.sharedWithMe:
        return drive.isSharedWithMe && !drive.isHidden;
      case DriveScope.hidden:
        return drive.isHidden;
    }
  }
}

/// How many drives each scope would show, for the sidebar to report.
///
/// Counted over everything rather than over what is on screen, because a scope
/// reading zero is exactly the fact a reader wants before clicking it.
class DriveScopeCounts {
  const DriveScopeCounts(this._counts);

  factory DriveScopeCounts.of(List<DriveListItem> drives) {
    return DriveScopeCounts({
      for (final scope in DriveScope.values)
        scope: drives.where(scope.matches).length,
    });
  }

  final Map<DriveScope, int> _counts;

  int operator [](DriveScope scope) => _counts[scope] ?? 0;

  @override
  bool operator ==(Object other) =>
      other is DriveScopeCounts &&
      DriveScope.values.every((s) => other[s] == this[s]);

  @override
  int get hashCode => Object.hashAll(DriveScope.values.map((s) => this[s]));
}
