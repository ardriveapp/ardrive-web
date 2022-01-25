part of 'upload_cubit.dart';

@immutable
abstract class UploadState extends Equatable {
  @override
  List<Object?> get props => [];
}

class UploadPreparationInProgress extends UploadState {
  final bool isArConnect;

  UploadPreparationInProgress({this.isArConnect = false});
  @override
  List<Object> get props => [isArConnect];
}

class UploadPreparationFailure extends UploadState {}

class UploadBundlingInProgress extends UploadState {
  final bool isArConnect;

  UploadBundlingInProgress({this.isArConnect = false});
  @override
  List<Object> get props => [isArConnect];
}

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
  final CostEstimate costEstimate;

  /// Whether or not the user has sufficient AR to cover the `totalCost`.
  final bool sufficientArBalance;

  /// Whether or not the upload will be made public ie. without encryption.
  final bool uploadIsPublic;

  final MappedUploadHandles mappedUploadHandles;
  UploadReady({
    required this.costEstimate,
    required this.sufficientArBalance,
    required this.uploadIsPublic,
    required this.mappedUploadHandles,
  });

  @override
  List<Object?> get props => [
        costEstimate,
        sufficientArBalance,
        mappedUploadHandles,
      ];
}

class UploadInProgress extends UploadState {
  final MappedUploadHandles mappedUploadHandles;
  final int _equatableBust = DateTime.now().millisecondsSinceEpoch;

  UploadInProgress({
    required this.mappedUploadHandles,
  });

  @override
  List<Object?> get props => [mappedUploadHandles, _equatableBust];
}

class UploadFailure extends UploadState {}

class UploadComplete extends UploadState {}

class UploadWalletMismatch extends UploadState {}
