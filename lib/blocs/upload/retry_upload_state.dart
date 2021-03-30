part of 'retry_upload_cubit.dart';

@immutable
abstract class RetryUploadState extends Equatable {
  @override
  List<Object> get props => [];
}

class RetryUploadPreparationInProgress extends RetryUploadState {}

class RetryUploadPreparationFailure extends RetryUploadState {}

class RetryUploadFileConflict extends RetryUploadState {
  final List<String> conflictingFileNames;

  RetryUploadFileConflict({@required this.conflictingFileNames});

  @override
  List<Object> get props => [conflictingFileNames];
}

class RetryUploadFileTooLarge extends RetryUploadState {
  final List<String> tooLargeFileNames;

  RetryUploadFileTooLarge({@required this.tooLargeFileNames});

  @override
  List<Object> get props => [tooLargeFileNames];
}

/// [RetryUploadReady] means that the Retryupload is ready to be performed and is awaiting confirmation from the user.
class RetryUploadReady extends RetryUploadState {
  /// The cost to Retryupload the data, in AR.
  final String arUploadCost;

  /// The cost to Retryupload the data, in USD.
  ///
  /// Null if conversion rate could not be retrieved.
  final double usdUploadCost;

  /// The fee amount provided to PST holders.
  final BigInt pstFee;

  /// The sum of the Retryupload cost and fees.
  final BigInt totalCost;

  /// Whether or not the user has sufficient AR to cover the `totalCost`.
  final bool sufficientArBalance;

  /// Whether or not the Retryupload will be made public ie. without encryption.
  final bool uploadIsPublic;

  final List<FileUploadHandle> files;

  RetryUploadReady({
    @required this.arUploadCost,
    @required this.pstFee,
    @required this.totalCost,
    @required this.sufficientArBalance,
    @required this.uploadIsPublic,
    @required this.files,
    this.usdUploadCost,
  });

  @override
  List<Object> get props => [
        arUploadCost,
        usdUploadCost,
        pstFee,
        totalCost,
        sufficientArBalance,
        files
      ];
}

class RetryUploadInProgress extends RetryUploadState {
  final List<FileUploadHandle> files;

  final int _equatableBust = DateTime.now().millisecondsSinceEpoch;

  RetryUploadInProgress({this.files});

  @override
  List<Object> get props => [files, _equatableBust];
}

class RetryUploadFailure extends RetryUploadState {}

class RetryUploadComplete extends RetryUploadState {}
