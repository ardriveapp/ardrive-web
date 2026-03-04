part of 'fs_entry_snapshots_cubit.dart';

abstract class FsEntrySnapshotsState extends Equatable {
  const FsEntrySnapshotsState();

  @override
  List<Object?> get props => [];
}

class FsEntrySnapshotsInitial extends FsEntrySnapshotsState {}

class FsEntrySnapshotsLoading extends FsEntrySnapshotsState {}

class FsEntrySnapshotsSuccess extends FsEntrySnapshotsState {
  final List<SnapshotDisplayItem> snapshots;

  /// Whether the drive would benefit from creating a (new) snapshot.
  /// Based on the 1000 transaction threshold from PromptToSnapshotBloc.
  final bool shouldRecommendSnapshot;

  const FsEntrySnapshotsSuccess({
    required this.snapshots,
    this.shouldRecommendSnapshot = false,
  });

  @override
  List<Object?> get props => [snapshots, shouldRecommendSnapshot];
}

class FsEntrySnapshotsFailure extends FsEntrySnapshotsState {
  final String? errorMessage;

  const FsEntrySnapshotsFailure({this.errorMessage});

  @override
  List<Object?> get props => [errorMessage];
}
