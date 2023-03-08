part of 'fs_entry_rename_cubit.dart';

abstract class FsEntryRenameState extends Equatable {
  final bool isRenamingFolder;

  const FsEntryRenameState({required this.isRenamingFolder});

  @override
  List<Object> get props => [isRenamingFolder];
}

class FsEntryRenameInitializing extends FsEntryRenameState {
  const FsEntryRenameInitializing({required bool isRenamingFolder})
      : super(isRenamingFolder: isRenamingFolder);
}

class FsEntryRenameInitialized extends FsEntryRenameState {
  const FsEntryRenameInitialized({required bool isRenamingFolder})
      : super(isRenamingFolder: isRenamingFolder);
}

class FolderEntryRenameInProgress extends FsEntryRenameState {
  const FolderEntryRenameInProgress() : super(isRenamingFolder: true);
}

class FolderEntryRenameSuccess extends FsEntryRenameState {
  const FolderEntryRenameSuccess() : super(isRenamingFolder: true);
}

class FolderEntryRenameFailure extends FsEntryRenameState {
  const FolderEntryRenameFailure() : super(isRenamingFolder: true);
}

class EntityAlreadyExists extends FsEntryRenameState {
  const EntityAlreadyExists(
    this.entityName, {
    required bool isRenamingFolder,
  }) : super(isRenamingFolder: isRenamingFolder);

  final String entityName;
}

class FolderEntryRenameWalletMismatch extends FsEntryRenameState {
  const FolderEntryRenameWalletMismatch() : super(isRenamingFolder: true);
}

class FileEntryRenameInProgress extends FsEntryRenameState {
  const FileEntryRenameInProgress() : super(isRenamingFolder: false);
}

class FileEntryRenameSuccess extends FsEntryRenameState {
  const FileEntryRenameSuccess() : super(isRenamingFolder: false);
}

class FileEntryRenameFailure extends FsEntryRenameState {
  const FileEntryRenameFailure() : super(isRenamingFolder: false);
}

class FileEntryRenameWalletMismatch extends FsEntryRenameState {
  const FileEntryRenameWalletMismatch() : super(isRenamingFolder: false);
}
