part of 'fs_entry_license_bloc.dart';

abstract class FsEntryLicenseState extends Equatable {
  const FsEntryLicenseState();

  @override
  List<Object> get props => [];
}

class FsEntryLicenseLoadInProgress extends FsEntryLicenseState {
  const FsEntryLicenseLoadInProgress() : super();
}

class FsEntryLicenseNoFiles extends FsEntryLicenseState {
  const FsEntryLicenseNoFiles() : super();
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
  final bool isPaymentError;
  const FsEntryLicenseFailure({this.isPaymentError = false}) : super();

  @override
  List<Object> get props => [isPaymentError];
}

class FsEntryLicenseComplete extends FsEntryLicenseState {
  const FsEntryLicenseComplete() : super();
}
