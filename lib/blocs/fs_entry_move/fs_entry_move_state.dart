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
  final List<SelectedItem> itemsToMove;

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
  final List<String> folderNames;
  final List<String> fileNames;
  const FsEntryMoveNameConflict({
    required this.folderNames,
    required this.fileNames,
  }) : super();
  @override
  List<Object> get props => [folderNames, fileNames];
}
