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

class UploadPreparationInitialized extends UploadState {}

class UploadSigningInProgress extends UploadState {
  final UploadPlan uploadPlan;
  final bool isArConnect;

  UploadSigningInProgress({required this.uploadPlan, this.isArConnect = false});
  @override
  List<Object> get props => [uploadPlan, isArConnect];
}

class UploadFileConflict extends UploadState {
  final List<String> conflictingFileNames;
  final bool areAllFilesConflicting;

  UploadFileConflict({
    required this.conflictingFileNames,
    required this.areAllFilesConflicting,
  });

  @override
  List<Object> get props => [conflictingFileNames];
}

class UploadFolderNameConflict extends UploadFileConflict {
  UploadFolderNameConflict({
    required List<String> conflictingFileNames,
    required bool areAllFilesConflicting,
  }) : super(
          conflictingFileNames: conflictingFileNames,
          areAllFilesConflicting: areAllFilesConflicting,
        );
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

  final UploadPlan uploadPlan;
  UploadReady({
    required this.costEstimate,
    required this.sufficientArBalance,
    required this.uploadIsPublic,
    required this.uploadPlan,
  });

  @override
  List<Object?> get props => [
        costEstimate,
        sufficientArBalance,
        uploadPlan,
      ];
}

class UploadInProgress extends UploadState {
  final UploadPlan uploadPlan;
  final int _equatableBust = DateTime.now().millisecondsSinceEpoch;

  UploadInProgress({
    required this.uploadPlan,
  });

  @override
  List<Object?> get props => [uploadPlan, _equatableBust];
}

class UploadFailure extends UploadState {}

class UploadComplete extends UploadState {}

class UploadWalletMismatch extends UploadState {}
