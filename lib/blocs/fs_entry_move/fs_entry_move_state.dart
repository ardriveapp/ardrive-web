part of 'fs_entry_move_bloc.dart';

abstract class FsEntryMoveState extends Equatable {
  const FsEntryMoveState();

  @override
  List<Object> get props => [];
}

class FsEntryMoveLoadInProgress extends FsEntryMoveState {
  const FsEntryMoveLoadInProgress() : super();
}

class FsEntryMoveLoadSuccess extends FsEntryMoveState {
  final bool viewingRootFolder;
  final FolderWithContents viewingFolder;

  /// The id of the folder/file entry being moved.
  final List<MoveItem> itemsToMove;

  const FsEntryMoveLoadSuccess({
    required this.viewingRootFolder,
    required this.viewingFolder,
    required this.itemsToMove,
  }) : super();
  @override
  List<Object> get props => [viewingRootFolder, viewingFolder, itemsToMove];
}

class FsEntryMoveWalletMismatch extends FsEntryMoveState {
  const FsEntryMoveWalletMismatch() : super();
}

class FsEntryMoveSuccess extends FsEntryMoveState {
  const FsEntryMoveSuccess() : super();
}

class FsEntryMoveNameConflict extends FsEntryMoveState {
  final List<MoveItem> conflictingItems;
  final FolderEntry folderInView;

  final List<MoveItem> allItems;

  const FsEntryMoveNameConflict({
    required this.conflictingItems,
    required this.folderInView,
    required this.allItems,
  }) : super();

  bool areAllItemsConflicting() => conflictingItems.length == allItems.length;

  List<String> conflictingFileNames() => conflictingItems
      .whereType<SelectedFile>()
      .map((e) => e.item.name)
      .toList();

  List<String> conflictingFolderNames() => conflictingItems
      .whereType<SelectedFolder>()
      .map((e) => e.item.name)
      .toList();

  @override
  List<Object> get props => [conflictingItems, folderInView];
}
