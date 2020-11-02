part of 'fs_entry_move_cubit.dart';

abstract class FsEntryMoveState extends Equatable {
  final bool isMovingFolder;

  const FsEntryMoveState({@required this.isMovingFolder});

  @override
  List<Object> get props => [isMovingFolder];
}

class FsEntryMoveFolderLoadInProgress extends FsEntryMoveState {
  FsEntryMoveFolderLoadInProgress({@required bool isMovingFolder})
      : super(isMovingFolder: isMovingFolder);
}

class FsEntryMoveFolderLoadSuccess extends FsEntryMoveState {
  final bool viewingRootFolder;
  final FolderWithContents viewingFolder;

  FsEntryMoveFolderLoadSuccess({
    @required this.viewingRootFolder,
    @required this.viewingFolder,
    @required bool isMovingFolder,
  }) : super(isMovingFolder: isMovingFolder);

  @override
  List<Object> get props => [viewingRootFolder, viewingFolder, isMovingFolder];
}

class FolderEntryMoveInProgress extends FsEntryMoveState {
  FolderEntryMoveInProgress() : super(isMovingFolder: true);
}

class FolderEntryMoveSuccess extends FsEntryMoveState {
  FolderEntryMoveSuccess() : super(isMovingFolder: true);
}

class FolderEntryMoveFailure extends FsEntryMoveState {
  FolderEntryMoveFailure() : super(isMovingFolder: true);
}

class FileEntryMoveInProgress extends FsEntryMoveState {
  FileEntryMoveInProgress() : super(isMovingFolder: false);
}

class FileEntryMoveSuccess extends FsEntryMoveState {
  FileEntryMoveSuccess() : super(isMovingFolder: false);
}

class FileEntryMoveFailure extends FsEntryMoveState {
  FileEntryMoveFailure() : super(isMovingFolder: false);
}
