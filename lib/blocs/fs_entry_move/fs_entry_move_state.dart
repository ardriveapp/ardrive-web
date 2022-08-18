part of 'fs_entry_move_cubit.dart';

abstract class FsEntryMoveState extends Equatable {
  final bool isMovingFolder;

  const FsEntryMoveState({required this.isMovingFolder});

  @override
  List<Object> get props => [isMovingFolder];
}

class FsEntryMoveFolderLoadInProgress extends FsEntryMoveState {
  const FsEntryMoveFolderLoadInProgress({required bool isMovingFolder})
      : super(isMovingFolder: isMovingFolder);
}

class FsEntryMoveFolderLoadSuccess extends FsEntryMoveState {
  final bool viewingRootFolder;
  final FolderWithContents viewingFolder;

  /// The id of the folder/file entry being moved.
  final String movingEntryId;

  const FsEntryMoveFolderLoadSuccess({
    required this.viewingRootFolder,
    required this.viewingFolder,
    required this.movingEntryId,
    required bool isMovingFolder,
  }) : super(isMovingFolder: isMovingFolder);

  @override
  List<Object> get props =>
      [viewingRootFolder, viewingFolder, movingEntryId, isMovingFolder];
}

class FsEntryMoveNameConflict extends FsEntryMoveState {
  final String name;
  const FsEntryMoveNameConflict({
    required this.name,
  }) : super(
          isMovingFolder: true,
        );
  @override
  List<Object> get props => [name];
}

class FolderEntryMoveInProgress extends FsEntryMoveState {
  const FolderEntryMoveInProgress() : super(isMovingFolder: true);
}

class FolderEntryMoveSuccess extends FsEntryMoveState {
  const FolderEntryMoveSuccess() : super(isMovingFolder: true);
}

class FolderEntryMoveFailure extends FsEntryMoveState {
  const FolderEntryMoveFailure() : super(isMovingFolder: true);
}

class FolderEntryMoveWalletMismatch extends FsEntryMoveState {
  const FolderEntryMoveWalletMismatch() : super(isMovingFolder: true);
}

class FileEntryMoveInProgress extends FsEntryMoveState {
  const FileEntryMoveInProgress() : super(isMovingFolder: false);
}

class FileEntryMoveSuccess extends FsEntryMoveState {
  const FileEntryMoveSuccess() : super(isMovingFolder: false);
}

class FileEntryMoveFailure extends FsEntryMoveState {
  const FileEntryMoveFailure() : super(isMovingFolder: false);
}

class FileEntryMoveWalletMismatch extends FsEntryMoveState {
  const FileEntryMoveWalletMismatch() : super(isMovingFolder: false);
}
