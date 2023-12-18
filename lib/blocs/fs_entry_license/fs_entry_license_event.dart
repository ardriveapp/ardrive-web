part of 'fs_entry_license_bloc.dart';

abstract class FsEntryLicenseEvent extends Equatable {
  const FsEntryLicenseEvent();

  @override
  List<Object?> get props => [];
}

class FsEntryLicenseSelect extends FsEntryLicenseEvent {
  const FsEntryLicenseSelect() : super();
}

class FsEntryLicenseConfigurationBack extends FsEntryLicenseEvent {
  const FsEntryLicenseConfigurationBack() : super();
}

class FsEntryLicenseConfigurationSubmit extends FsEntryLicenseEvent {
  final LicenseParams? licenseParams;

  const FsEntryLicenseConfigurationSubmit({
    this.licenseParams,
  }) : super();

  @override
  List<Object?> get props => [licenseParams];
}

class FsEntryLicenseReviewBack extends FsEntryLicenseEvent {
  const FsEntryLicenseReviewBack() : super();
}

class FsEntryLicenseReviewConfirm extends FsEntryLicenseEvent {
  const FsEntryLicenseReviewConfirm() : super();
}
