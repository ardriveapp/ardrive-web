part of 'fs_entry_license_bloc.dart';

abstract class FsEntryLicenseState extends Equatable {
  const FsEntryLicenseState();

  @override
  List<Object> get props => [];
}

class FsEntryLicenseLoadInProgress extends FsEntryLicenseState {
  const FsEntryLicenseLoadInProgress() : super();
}

class FsEntryLicenseSelecting extends FsEntryLicenseState {
  const FsEntryLicenseSelecting() : super();
}

class FsEntryLicenseConfiguring extends FsEntryLicenseState {
  const FsEntryLicenseConfiguring() : super();
}

class FsEntryLicenseReviewing extends FsEntryLicenseState {
  const FsEntryLicenseReviewing() : super();
}

class FsEntryLicenseWalletMismatch extends FsEntryLicenseState {
  const FsEntryLicenseWalletMismatch() : super();
}

class FsEntryLicenseSuccess extends FsEntryLicenseState {
  const FsEntryLicenseSuccess() : super();
}

class FsEntryLicenseFailure extends FsEntryLicenseState {
  const FsEntryLicenseFailure() : super();
}

class FsEntryLicenseComplete extends FsEntryLicenseState {
  const FsEntryLicenseComplete() : super();
}
