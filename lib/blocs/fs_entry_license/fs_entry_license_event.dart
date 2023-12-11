part of 'fs_entry_license_bloc.dart';

abstract class FsEntryLicenseEvent extends Equatable {
  const FsEntryLicenseEvent();

  @override
  List<Object> get props => [];
}

class FsEntryLicenseInitial extends FsEntryLicenseEvent {
  const FsEntryLicenseInitial() : super();
}

class FsEntryLicenseUpdateTargetFolder extends FsEntryLicenseEvent {
  final String folderId;
  const FsEntryLicenseUpdateTargetFolder({required this.folderId}) : super();
  @override
  List<Object> get props => [folderId];
}

class FsEntryLicenseGoBackToParent extends FsEntryLicenseEvent {
  final FolderEntry folderInView;
  const FsEntryLicenseGoBackToParent({required this.folderInView}) : super();
  @override
  List<Object> get props => [folderInView];
}

class FsEntryLicenseSubmit extends FsEntryLicenseEvent {
  final FolderEntry folderInView;
  const FsEntryLicenseSubmit({
    required this.folderInView,
  }) : super();
  @override
  List<Object> get props => [folderInView];
}

class FsEntryLicenseSkipConflicts extends FsEntryLicenseEvent {
  final FolderEntry folderInView;
  final List<ArDriveDataTableItem> conflictingItems;
  const FsEntryLicenseSkipConflicts({
    required this.folderInView,
    required this.conflictingItems,
  }) : super();
  @override
  List<Object> get props => [folderInView, conflictingItems];
}
