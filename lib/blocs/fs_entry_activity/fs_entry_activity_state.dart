part of 'fs_entry_activity_cubit.dart';

abstract class FsEntryActivityState extends Equatable {
  const FsEntryActivityState();

  @override
  List<Object> get props => [];
}

class FsEntryActivityInitial extends FsEntryActivityState {}

class FsEntryActivitySuccess<T> extends FsEntryActivityState {
  final List<T> revisions;

  const FsEntryActivitySuccess({required this.revisions});

  @override
  List<Object> get props => [revisions];
}

class FsEntryActivityFailure extends FsEntryActivityState {}

/// A drive with no history on this device whose history could not be read
/// from the network either, so the only way to see it is to sync it.
class FsEntryActivityDriveNotSynced extends FsEntryActivityState {}
