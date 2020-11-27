part of 'fs_entry_activity_cubit.dart';

abstract class FsEntryActivityState extends Equatable {
  const FsEntryActivityState();

  @override
  List<Object> get props => [];
}

class FsEntryActivityInitial extends FsEntryActivityState {}

class FsEntryActivitySuccess<T> extends FsEntryActivityState {
  final List<T> revisions;

  FsEntryActivitySuccess({this.revisions});
}

class FsEntryActivityFailure extends FsEntryActivityState {}
