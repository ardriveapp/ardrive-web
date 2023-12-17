part of 'fs_entry_license_bloc.dart';

abstract class FsEntryLicenseState extends Equatable {
  const FsEntryLicenseState();

  @override
  List<Object> get props => [];
}

class FsEntryLicenseSelecting extends FsEntryLicenseState {
  const FsEntryLicenseSelecting() : super();
}

class FsEntryLicenseConfiguring extends FsEntryLicenseState {
  final LicenseInfo licenseInfo;

  const FsEntryLicenseConfiguring({required this.licenseInfo}) : super();
}

class FsEntryLicenseLoadInProgress extends FsEntryLicenseState {
  const FsEntryLicenseLoadInProgress() : super();
}

class FsEntryLicenseWalletMismatch extends FsEntryLicenseState {
  const FsEntryLicenseWalletMismatch() : super();
}

class FsEntryLicenseSuccess extends FsEntryLicenseState {
  const FsEntryLicenseSuccess() : super();
}
