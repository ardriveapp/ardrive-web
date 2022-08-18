part of 'fs_entry_move_bloc.dart';

abstract class FsEntryMoveEvent extends Equatable {
  const FsEntryMoveEvent();

  @override
  List<Object> get props => [];
}

class FsEntryMoveInitial extends FsEntryMoveEvent {
  const FsEntryMoveInitial() : super();
}

class FsEntryMoveUpdateTargetFolder extends FsEntryMoveEvent {
  const FsEntryMoveUpdateTargetFolder() : super();
}

class FsEntryMoveGoBackToParent extends FsEntryMoveEvent {
  const FsEntryMoveGoBackToParent() : super();
}

class FsEntryMoveSubmit extends FsEntryMoveEvent {
  final FolderEntry folderInView;
  const FsEntryMoveSubmit({required this.folderInView}) : super();
  @override
  List<Object> get props => [folderInView];
}

class FsEntryMoveSkipConflicts extends FsEntryMoveEvent {
  final FolderEntry folderInView;
  const FsEntryMoveSkipConflicts({required this.folderInView}) : super();
  @override
  List<Object> get props => [folderInView];
}
