part of 'fs_entry_rename_cubit.dart';

abstract class FsEntryRenameState extends Equatable {
  final bool isRenamingFolder;

  const FsEntryRenameState({@required this.isRenamingFolder});

  @override
  List<Object> get props => [isRenamingFolder];
}

class FsEntryRenameInitializing extends FsEntryRenameState {
  FsEntryRenameInitializing({@required bool isRenamingFolder})
      : super(isRenamingFolder: isRenamingFolder);
}

class FsEntryRenameInitialized extends FsEntryRenameState {
  FsEntryRenameInitialized({@required bool isRenamingFolder})
      : super(isRenamingFolder: isRenamingFolder);
}

class FolderEntryRenameInProgress extends FsEntryRenameState {
  FolderEntryRenameInProgress() : super(isRenamingFolder: true);
}

class FolderEntryRenameSuccess extends FsEntryRenameState {
  FolderEntryRenameSuccess() : super(isRenamingFolder: true);
}

class FolderEntryRenameFailure extends FsEntryRenameState {
  FolderEntryRenameFailure() : super(isRenamingFolder: true);
}

class FileEntryRenameInProgress extends FsEntryRenameState {
  FileEntryRenameInProgress() : super(isRenamingFolder: false);
}

class FileEntryRenameSuccess extends FsEntryRenameState {
  FileEntryRenameSuccess() : super(isRenamingFolder: false);
}

class FileEntryRenameFailure extends FsEntryRenameState {
  FileEntryRenameFailure() : super(isRenamingFolder: false);
}
