part of 'fs_entry_license_bloc.dart';

abstract class FsEntryLicenseEvent extends Equatable {
  const FsEntryLicenseEvent();

  @override
  List<Object?> get props => [];
}

class FsEntryLicenseInitial extends FsEntryLicenseEvent {
  const FsEntryLicenseInitial() : super();
}

/// The license, or one of its settings, changed: the review reads what the
/// write costs again, or waits while the settings are not complete.
class FsEntryLicenseSettingsChanged extends FsEntryLicenseEvent {
  const FsEntryLicenseSettingsChanged() : super();
}

class FsEntryLicenseReviewConfirm extends FsEntryLicenseEvent {
  const FsEntryLicenseReviewConfirm() : super();
}

class FsEntryLicenseSuccessClose extends FsEntryLicenseEvent {
  const FsEntryLicenseSuccessClose() : super();
}

/// Reads the cost again: Try again, or after credits were added.
class FsEntryLicenseCostRefresh extends FsEntryLicenseEvent {
  const FsEntryLicenseCostRefresh() : super();
}
