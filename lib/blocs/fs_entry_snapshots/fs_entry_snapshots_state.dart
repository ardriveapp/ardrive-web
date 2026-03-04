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

  const FsEntrySnapshotsSuccess({required this.snapshots});

  @override
  List<Object?> get props => [snapshots];
}

class FsEntrySnapshotsFailure extends FsEntrySnapshotsState {
  final String? errorMessage;

  const FsEntrySnapshotsFailure({this.errorMessage});

  @override
  List<Object?> get props => [errorMessage];
}
