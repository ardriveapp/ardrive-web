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

class FsEntryLicenseReviewing extends FsEntryLicenseState {
  /// What writing the license costs, and whether it can go ahead. Null while
  /// it is read.
  final UploadReviewSummary? summary;

  /// The cost could not be worked out for a reason other than Turbo or the
  /// connection, so the notice does not blame either.
  final bool pricingFailed;

  /// The license's settings are not complete yet, such as a Creative
  /// Commons license with no type picked: nothing is priced or written.
  final bool incomplete;

  /// The license is being written: the dialog stays, its primary busy.
  final bool busy;

  /// The last write failed for a reason other than payment. The dialog says
  /// so, and Add license tries again, sending only what did not get through.
  final bool failed;

  const FsEntryLicenseReviewing({
    this.summary,
    this.pricingFailed = false,
    this.incomplete = false,
    this.busy = false,
    this.failed = false,
  }) : super();

  @override
  List<Object?> get props =>
      [summary, pricingFailed, incomplete, busy, failed];
}

class FsEntryLicenseWalletMismatch extends FsEntryLicenseState {
  const FsEntryLicenseWalletMismatch() : super();
}

class FsEntryLicenseSuccess extends FsEntryLicenseState {
  const FsEntryLicenseSuccess() : super();
}

class FsEntryLicenseComplete extends FsEntryLicenseState {
  const FsEntryLicenseComplete() : super();
}
