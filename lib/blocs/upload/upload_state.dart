part of 'upload_cubit.dart';

@immutable
abstract class UploadState extends Equatable {
  @override
  List<Object?> get props => [];
}

class UploadPreparationInProgress extends UploadState {}

class UploadPreparationFailure extends UploadState {}

class UploadBundlingInProgress extends UploadState {}

class UploadFileConflict extends UploadState {
  final List<String> conflictingFileNames;

  UploadFileConflict({required this.conflictingFileNames});

  @override
  List<Object> get props => [conflictingFileNames];
}

class UploadFileTooLarge extends UploadState {
  final List<String> tooLargeFileNames;
  final bool isPrivate;
  UploadFileTooLarge(
      {required this.tooLargeFileNames, required this.isPrivate});

  @override
  List<Object> get props => [tooLargeFileNames];
}

/// [UploadReady] means that the upload is ready to be performed and is awaiting confirmation from the user.
class UploadReady extends UploadState {
  /// The cost to upload the data, in AR.
  final String arUploadCost;

  /// The cost to upload the data, in USD.
  ///
  /// Null if conversion rate could not be retrieved.
  final double? usdUploadCost;

  /// The fee amount provided to PST holders.
  final BigInt pstFee;

  /// The sum of the upload cost and fees.
  final BigInt totalCost;

  /// Whether or not the user has sufficient AR to cover the `totalCost`.
  final bool sufficientArBalance;

  /// Whether or not the upload will be made public ie. without encryption.
  final bool uploadIsPublic;

  final List<FileUploadHandle> files;
  final List<MultiFileUploadHandle> bundles;

  UploadReady({
    required this.arUploadCost,
    required this.pstFee,
    required this.totalCost,
    required this.sufficientArBalance,
    required this.uploadIsPublic,
    required this.files,
    required this.bundles,
    this.usdUploadCost,
  });

  @override
  List<Object?> get props => [
        arUploadCost,
        usdUploadCost,
        pstFee,
        totalCost,
        sufficientArBalance,
        files
      ];
}

class UploadInProgress extends UploadState {
  final List<UploadHandle>? files;

  final int _equatableBust = DateTime.now().millisecondsSinceEpoch;
  UploadInProgress({this.files});

  @override
  List<Object?> get props => [files, _equatableBust];
}

class UploadFailure extends UploadState {}

class UploadComplete extends UploadState {}

class UploadWalletMismatch extends UploadState {}
