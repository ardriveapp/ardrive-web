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
  final LicenseInfo licenseInfo;
  final LicenseParams licenseParams;

  const FsEntryLicenseSubmit({
    required this.licenseInfo,
    required this.licenseParams,
  }) : super();
  @override
  List<Object> get props => [licenseInfo, licenseParams];
}
