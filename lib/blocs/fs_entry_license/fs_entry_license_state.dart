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
  final FolderWithContents viewingFolder;

  /// The id of the folder/file entry being licensed.
  final List<ArDriveDataTableItem> itemsToLicense;

  const FsEntryLicenseLoadSuccess({
    required this.viewingFolder,
    required this.itemsToLicense,
  }) : super();
  @override
  List<Object> get props => [viewingFolder, itemsToLicense];
}

class FsEntryLicenseWalletMismatch extends FsEntryLicenseState {
  const FsEntryLicenseWalletMismatch() : super();
}

class FsEntryLicenseSuccess extends FsEntryLicenseState {
  const FsEntryLicenseSuccess() : super();
}
