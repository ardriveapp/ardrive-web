part of 'fs_entry_license_bloc.dart';

abstract class FsEntryLicenseEvent extends Equatable {
  const FsEntryLicenseEvent();

  @override
  List<Object> get props => [];
}

class FsEntryLicenseInitial extends FsEntryLicenseEvent {
  const FsEntryLicenseInitial() : super();
}

class FsEntryLicenseSubmit extends FsEntryLicenseEvent {
  final FolderEntry folderInView;
  const FsEntryLicenseSubmit({
    required this.folderInView,
  }) : super();
  @override
  List<Object> get props => [folderInView];
}
