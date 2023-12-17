part of 'fs_entry_license_bloc.dart';

abstract class FsEntryLicenseEvent extends Equatable {
  const FsEntryLicenseEvent();

  @override
  List<Object?> get props => [];
}

class FsEntryLicenseSelect extends FsEntryLicenseEvent {
  const FsEntryLicenseSelect() : super();
}

class FsEntryLicenseSubmitConfiguration extends FsEntryLicenseEvent {
  final LicenseParams? licenseParams;

  const FsEntryLicenseSubmitConfiguration({
    this.licenseParams,
  }) : super();

  @override
  List<Object?> get props => [licenseParams];
}

class FsEntryLicenseReviewConfirm extends FsEntryLicenseEvent {
  const FsEntryLicenseReviewConfirm() : super();
}
