part of 'upload_cubit.dart';

@immutable
abstract class UploadState extends Equatable {
  @override
  List<Object> get props => [];
}

class UploadPreparationInProgress extends UploadState {}

class UploadPreparationFailure extends UploadState {}

class UploadFileConflict extends UploadState {
  final List<String> conflictingFileNames;

  UploadFileConflict({@required this.conflictingFileNames});

  @override
  List<Object> get props => [conflictingFileNames];
}

/// [UploadReady] means that the upload is ready to be performed and is awaiting confirmation from the user.
class UploadReady extends UploadState {
  /// The cost to upload the data.
  final BigInt uploadCost;

  /// The fee amount provided to PST holders.
  final BigInt pstFee;

  /// The sum of the upload cost and fees.
  final BigInt totalCost;

  /// Whether or not the user has sufficient AR to cover the `totalCost`.
  final bool sufficientArBalance;

  /// Whether or not the upload will be made public ie. without encryption.
  final bool uploadIsPublic;

  final num usdCost;

  final List<FileUploadHandle> files;

  UploadReady({
    @required this.uploadCost,
    @required this.pstFee,
    @required this.totalCost,
    @required this.sufficientArBalance,
    @required this.uploadIsPublic,
    @required this.files,
    @required this.usdCost,
  });

  @override
  List<Object> get props =>
      [uploadCost, pstFee, totalCost, sufficientArBalance, files];
}

class UploadInProgress extends UploadState {
  final List<FileUploadHandle> files;

  final int _equatableBust = DateTime.now().millisecondsSinceEpoch;

  UploadInProgress({this.files});

  @override
  List<Object> get props => [files, _equatableBust];
}

class UploadFailure extends UploadState {}

class UploadComplete extends UploadState {}
