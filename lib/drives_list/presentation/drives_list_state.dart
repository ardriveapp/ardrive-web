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
  const DrivesListLoading({this.drivesRead = 0, this.drivesFound = 0});

  /// How far the drive-list read has got, when it is the thing being waited
  /// on. Carried on the state rather than read off `SyncCubit` at the widget,
  /// because `DrivesListBody` draws what it is given and reaches for nothing.
  final int drivesRead;
  final int drivesFound;

  bool get hasCount => drivesFound > 0;

  @override
  List<Object> get props => [drivesRead, drivesFound];
}

/// We looked, and this account genuinely has no drives yet.
class DrivesListEmpty extends DrivesListState {}

/// We asked and could not find out. Never rendered as emptiness.
class DrivesListUnavailable extends DrivesListState {}

/// The list.
class DrivesListLoaded extends DrivesListState {
  const DrivesListLoaded({required this.drives});

  final List<DriveListItem> drives;

  /// Whether nothing here has ever been walked.
  ///
  /// With sync-on-login off this is the state a first login lands in, and it
  /// is the one moment where offering to sync everything at once is a service
  /// rather than a nag. Once a single drive has been synced the offer goes
  /// away, because the per-drive answer is on the row.
  bool get nothingHasEverBeenSynced =>
      drives.isNotEmpty && drives.every((drive) => !drive.hasBeenWalked);

  /// Whether a sync is running over these drives right now.
  bool get isSyncing => drives.any((drive) => drive.isSyncing);

  @override
  List<Object?> get props => [drives];
}
