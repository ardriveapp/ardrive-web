part of 'fs_entry_license_bloc.dart';

abstract class FsEntryLicenseState extends Equatable {
  const FsEntryLicenseState();

  @override
  List<Object> get props => [];
}

class FsEntryLicenseLoadInProgress extends FsEntryLicenseState {
  const FsEntryLicenseLoadInProgress() : super();
}

class FsEntryLicenseLoadSuccess extends FsEntryLicenseState {
  final bool viewingRootFolder;
  final FolderWithContents viewingFolder;

  /// The id of the folder/file entry being licensed.
  final List<ArDriveDataTableItem> itemsToLicense;

  const FsEntryLicenseLoadSuccess({
    required this.viewingRootFolder,
    required this.viewingFolder,
    required this.itemsToLicense,
  }) : super();
  @override
  List<Object> get props => [viewingRootFolder, viewingFolder, itemsToLicense];
}

class FsEntryLicenseWalletMismatch extends FsEntryLicenseState {
  const FsEntryLicenseWalletMismatch() : super();
}

class FsEntryLicenseSuccess extends FsEntryLicenseState {
  const FsEntryLicenseSuccess() : super();
}

class FsEntryLicenseNameConflict extends FsEntryLicenseState {
  final List<ArDriveDataTableItem> conflictingItems;
  final FolderEntry folderInView;

  final List<ArDriveDataTableItem> allItems;

  const FsEntryLicenseNameConflict({
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
