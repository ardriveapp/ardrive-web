part of 'fs_entry_license_bloc.dart';

abstract class FsEntryLicenseState extends Equatable {
  const FsEntryLicenseState();

  @override
  List<Object?> get props => [];
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
  /// What writing the license costs, and whether it can go ahead. Null while
  /// it is read.
  final UploadReviewSummary? summary;

  const FsEntryLicenseReviewing({this.summary}) : super();

  @override
  List<Object?> get props => [summary];
}

class FsEntryLicenseWalletMismatch extends FsEntryLicenseState {
  const FsEntryLicenseWalletMismatch() : super();
}

class FsEntryLicenseSuccess extends FsEntryLicenseState {
  const FsEntryLicenseSuccess() : super();
}

/// The write failed for a reason other than payment. A refused payment goes
/// back to [FsEntryLicenseReviewing], where Add credits is.
class FsEntryLicenseFailure extends FsEntryLicenseState {
  const FsEntryLicenseFailure() : super();
}

class FsEntryLicenseComplete extends FsEntryLicenseState {
  const FsEntryLicenseComplete() : super();
}
