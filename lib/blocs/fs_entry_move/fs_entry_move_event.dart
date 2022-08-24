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
  final String folderId;
  const FsEntryMoveUpdateTargetFolder({required this.folderId}) : super();
  @override
  List<Object> get props => [folderId];
}

class FsEntryMoveGoBackToParent extends FsEntryMoveEvent {
  final FolderEntry folderInView;
  const FsEntryMoveGoBackToParent({required this.folderInView}) : super();
  @override
  List<Object> get props => [folderInView];
}

class FsEntryMoveSubmit extends FsEntryMoveEvent {
  final FolderEntry folderInView;
  final bool dryRun;
  const FsEntryMoveSubmit({
    required this.folderInView,
    this.dryRun = false,
  }) : super();
  @override
  List<Object> get props => [folderInView];
}

class FsEntryMoveSkipConflicts extends FsEntryMoveEvent {
  final FolderEntry folderInView;
  final List<SelectedItem> conflictingItems;
  final bool dryRun;
  const FsEntryMoveSkipConflicts({
    required this.folderInView,
    required this.conflictingItems,
    this.dryRun = false,
  }) : super();
  @override
  List<Object> get props => [folderInView, conflictingItems];
}
