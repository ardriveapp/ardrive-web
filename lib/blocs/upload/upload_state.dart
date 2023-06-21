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
  UploadFileTooLarge({
    required this.tooLargeFileNames,
    required this.hasFilesToUpload,
    required this.isPrivate,
  });

  final List<String> tooLargeFileNames;
  final bool hasFilesToUpload;
  final bool isPrivate;

  @override
  List<Object> get props => [tooLargeFileNames];
}

/// [UploadReady] means that the upload is ready to be performed and is awaiting confirmation from the user.
class UploadReady extends UploadState {
  /// The cost to upload the data, in AR.
  final UploadCostEstimate costEstimateAr;
  final UploadCostEstimate? costEstimateTurbo;

  /// Whether or not the user has sufficient AR to cover the `totalCost`.
  final bool sufficientArBalance;
  final bool isZeroBalance;

  final bool sufficentCreditsBalance;

  /// Whether or not the upload will be made public ie. without encryption.
  final bool uploadIsPublic;

  final UploadPlan uploadPlanForAR;
  final UploadPlan? uploadPlanForTurbo;
  final bool isTurboUploadPossible;
  final bool isFreeThanksToTurbo;

  final int uploadSize;

  final String credits;
  final String arBalance;
  final String turboCredits;
  final UploadMethod uploadMethod;

  UploadReady({
    required this.costEstimateAr,
    required this.sufficientArBalance,
    required this.uploadIsPublic,
    required this.uploadPlanForAR,
    required this.isFreeThanksToTurbo,
    required this.uploadSize,
    required this.credits,
    required this.arBalance,
    required this.sufficentCreditsBalance,
    required this.turboCredits,
    this.costEstimateTurbo,
    required this.isZeroBalance,
    this.uploadPlanForTurbo,
    required this.isTurboUploadPossible,
    required this.uploadMethod,
  });

  @override
  List<Object?> get props => [
        costEstimateAr,
        sufficientArBalance,
        uploadPlanForAR,
        isFreeThanksToTurbo,
      ];
}

class UploadInProgress extends UploadState {
  final UploadPlan uploadPlan;
  final int _equatableBust = DateTime.now().millisecondsSinceEpoch;
  final double progress;

  UploadInProgress({
    required this.uploadPlan,
    required this.progress,
  });

  @override
  List<Object?> get props => [uploadPlan, _equatableBust];
}

class UploadFailure extends UploadState {}

class UploadComplete extends UploadState {}

class UploadWalletMismatch extends UploadState {}

class UploadShowingWarning extends UploadState {
  final UploadWarningReason reason;

  UploadShowingWarning({required this.reason});

  @override
  List<Object> get props => [reason];
}

enum UploadWarningReason {
  /// The user is attempting to upload a file that is too large.
  fileTooLarge,
}
