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

  /// Whether nothing here has ever been walked *and* nothing is known about
  /// what any of it holds.
  ///
  /// With sync-on-login off this is the state a first login lands in, and it
  /// is the one moment where offering to sync everything at once is a service
  /// rather than a nag. Once a single drive has been synced the offer goes
  /// away, because the per-drive answer is on the row.
  ///
  /// The second half of that is why a file count is consulted as well as a
  /// block height. A brand new user creates one drive, uploads to it and lands
  /// here: every drive they own is unwalked, so `every` was trivially true and
  /// the card announced "Nothing has been synced yet - their contents have not
  /// been fetched yet" over a drive whose contents they had just put there
  /// themselves. The card's own words are the test: a drive whose figures are
  /// on screen has had its contents fetched, whoever fetched them.
  bool get nothingHasEverBeenSynced =>
      drives.isNotEmpty &&
      drives.every((drive) => !drive.hasBeenWalked && drive.fileCount == null);

  /// The drives the network has moved on without.
  ///
  /// Read off the rows for the same reason [failedDriveIds] is, and scoped for
  /// the same reason too: this is a claim about the list on screen, so filtering
  /// to Private must not leave a notice up about a public drive that is no
  /// longer in view.
  List<String> get drivesWithUnreadChanges => [
        for (final drive in drives)
          if (drive.hasUnreadChanges) drive.id,
      ];

  /// The drives the last sync could not read.
  ///
  /// Read off the rows rather than off a sync state, so it survives the sync
  /// state moving on - the failure is a property of the drive until something
  /// reads it successfully, not of the run that noticed.
  List<String> get failedDriveIds => [
        for (final drive in drives)
          if (drive.lastSyncFailed) drive.id,
      ];

  /// Whether a sync is running over these drives right now.
  bool get isSyncing => drives.any((drive) => drive.isSyncing);

  @override
  List<Object?> get props =>
      [drives, scope, counts, sort, sortAscending, selected];
}
