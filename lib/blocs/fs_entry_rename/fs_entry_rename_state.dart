part of 'fs_entry_rename_cubit.dart';

abstract class FsEntryRenameState extends Equatable {
  final bool isRenamingFolder;
  final String entryName;

  const FsEntryRenameState({
    required this.isRenamingFolder,
    required this.entryName,
  });

  @override
  List<Object> get props => [isRenamingFolder, entryName];
}

class FsEntryRenameInitializing extends FsEntryRenameState {
  const FsEntryRenameInitializing({
    required bool isRenamingFolder,
    required String entryName,
  }) : super(isRenamingFolder: isRenamingFolder, entryName: entryName);
}

class FsEntryRenameInitialized extends FsEntryRenameState {
  const FsEntryRenameInitialized({
    required bool isRenamingFolder,
    required String entryName,
  }) : super(isRenamingFolder: isRenamingFolder, entryName: entryName);
}

class FolderEntryRenameInProgress extends FsEntryRenameState {
  const FolderEntryRenameInProgress({required String entryName})
      : super(isRenamingFolder: true, entryName: entryName);
}

class FolderEntryRenameSuccess extends FsEntryRenameState {
  const FolderEntryRenameSuccess({required String entryName})
      : super(isRenamingFolder: true, entryName: entryName);
}

class FolderEntryRenameFailure extends FsEntryRenameState {
  const FolderEntryRenameFailure({required String entryName})
      : super(isRenamingFolder: true, entryName: entryName);
}

class FolderEntryRenameWalletMismatch extends FsEntryRenameState {
  const FolderEntryRenameWalletMismatch({required String entryName})
      : super(isRenamingFolder: true, entryName: entryName);
}

class FileEntryRenameInProgress extends FsEntryRenameState {
  const FileEntryRenameInProgress({required String entryName})
      : super(isRenamingFolder: false, entryName: entryName);
}

class FileEntryRenameSuccess extends FsEntryRenameState {
  const FileEntryRenameSuccess({required String entryName})
      : super(isRenamingFolder: false, entryName: entryName);
}

class FileEntryRenameFailure extends FsEntryRenameState {
  const FileEntryRenameFailure({required String entryName})
      : super(isRenamingFolder: false, entryName: entryName);
}

class FileEntryRenameWalletMismatch extends FsEntryRenameState {
  const FileEntryRenameWalletMismatch({required String entryName})
      : super(isRenamingFolder: false, entryName: entryName);
}
