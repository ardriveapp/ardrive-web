part of 'drives_list_cubit.dart';

/// The four answers this page is allowed to give, and no fifth.
///
/// They are the same four the explorer already uses, deliberately: loading is
/// not emptiness, emptiness is not failure, and failure never offers to create
/// a drive.
abstract class DrivesListState extends Equatable {
  const DrivesListState();

  @override
  List<Object?> get props => [];
}

/// We are still looking. Says so, and says nothing about what will be found.
class DrivesListLoading extends DrivesListState {
  const DrivesListLoading({this.syncState});

  /// The drive-list read this page is waiting on, when that is what is
  /// running. Carried here rather than read off `SyncCubit` at the widget,
  /// because `DrivesListBody` draws what it is given and reaches for nothing -
  /// which is why its tests need no providers.
  ///
  /// The whole state and not just a count: there are two phases with two
  /// different things to say, and the page is not the place to decide which.
  final SyncLoadingDrives? syncState;

  @override
  List<Object> get props => [
        syncState?.drivesRead ?? -1,
        syncState?.drivesFound ?? -1,
        syncState?.phase ?? '',
      ];
}

/// We looked, and this account genuinely has no drives yet.
class DrivesListEmpty extends DrivesListState {}

/// We asked and could not find out. Never rendered as emptiness.
class DrivesListUnavailable extends DrivesListState {}

/// The list.
class DrivesListLoaded extends DrivesListState {
  const DrivesListLoaded({
    required this.drives,
    this.scope = DriveScope.all,
    this.counts = const DriveScopeCounts({}),
    this.sort = DriveListSort.name,
    this.sortAscending = true,
    this.selected = const {},
  });

  /// The drives this scope shows, already filtered.
  final List<DriveListItem> drives;

  /// Which scope produced [drives].
  final DriveScope scope;

  /// What every scope would show, so the sidebar can put a count beside each
  /// one without holding its own copy of the list.
  final DriveScopeCounts counts;

  /// Which column [drives] is ordered by, so the header can mark it.
  final DriveListSort sort;

  /// Which way that column is ordered.
  final bool sortAscending;

  /// The drives the reader has ticked, if any.
  ///
  /// Empty means no selection rather than an empty one, and the controls read
  /// it that way: with nothing ticked, the action is still Sync All Drives.
  final Set<String> selected;

  /// The drives the network has moved on without.
  ///
  /// Read off the rows, so it survives the sync state moving on, and scoped to
  /// the list on screen: the sync menu's offer to sync the changed drives must
  /// not count a public drive while the page shows Private.
  List<String> get drivesWithUnreadChanges => [
        for (final drive in drives)
          if (drive.hasUnreadChanges) drive.id,
      ];

  @override
  List<Object?> get props =>
      [drives, scope, counts, sort, sortAscending, selected];
}
