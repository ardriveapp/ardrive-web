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
  final bool isButtonToUploadEnabled;

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
    required this.isButtonToUploadEnabled,
  });

// copyWith
  UploadReady copyWith({
    UploadCostEstimate? costEstimateAr,
    UploadCostEstimate? costEstimateTurbo,
    bool? sufficientArBalance,
    bool? isZeroBalance,
    bool? sufficentCreditsBalance,
    bool? uploadIsPublic,
    UploadPlan? uploadPlanForAR,
    UploadPlan? uploadPlanForTurbo,
    bool? isTurboUploadPossible,
    bool? isFreeThanksToTurbo,
    int? uploadSize,
    String? credits,
    String? arBalance,
    String? turboCredits,
    UploadMethod? uploadMethod,
    bool? isButtonToUploadEnabled,
  }) {
    return UploadReady(
      costEstimateAr: costEstimateAr ?? this.costEstimateAr,
      costEstimateTurbo: costEstimateTurbo ?? this.costEstimateTurbo,
      sufficientArBalance: sufficientArBalance ?? this.sufficientArBalance,
      isZeroBalance: isZeroBalance ?? this.isZeroBalance,
      sufficentCreditsBalance:
          sufficentCreditsBalance ?? this.sufficentCreditsBalance,
      uploadIsPublic: uploadIsPublic ?? this.uploadIsPublic,
      uploadPlanForAR: uploadPlanForAR ?? this.uploadPlanForAR,
      uploadPlanForTurbo: uploadPlanForTurbo ?? this.uploadPlanForTurbo,
      isTurboUploadPossible:
          isTurboUploadPossible ?? this.isTurboUploadPossible,
      isFreeThanksToTurbo: isFreeThanksToTurbo ?? this.isFreeThanksToTurbo,
      uploadSize: uploadSize ?? this.uploadSize,
      credits: credits ?? this.credits,
      arBalance: arBalance ?? this.arBalance,
      turboCredits: turboCredits ?? this.turboCredits,
      uploadMethod: uploadMethod ?? this.uploadMethod,
      isButtonToUploadEnabled:
          isButtonToUploadEnabled ?? this.isButtonToUploadEnabled,
    );
  }

  @override
  List<Object?> get props => [
        costEstimateAr,
        costEstimateTurbo,
        sufficientArBalance,
        isZeroBalance,
        sufficentCreditsBalance,
        uploadIsPublic,
        uploadPlanForAR,
        uploadPlanForTurbo,
        isTurboUploadPossible,
        isFreeThanksToTurbo,
        uploadSize,
        credits,
        arBalance,
        turboCredits,
        uploadMethod,
        isButtonToUploadEnabled,
      ];

  @override
  toString() => 'UploadReady { '
      'costEstimateAr: $costEstimateAr, '
      'costEstimateTurbo: $costEstimateTurbo, '
      'sufficientArBalance: $sufficientArBalance, '
      'isZeroBalance: $isZeroBalance, '
      'sufficentCreditsBalance: $sufficentCreditsBalance, '
      'uploadIsPublic: $uploadIsPublic, '
      'uploadPlanForAR: $uploadPlanForAR, '
      'uploadPlanForTurbo: $uploadPlanForTurbo, '
      'isTurboUploadPossible: $isTurboUploadPossible, '
      'isFreeThanksToTurbo: $isFreeThanksToTurbo, '
      'uploadSize: $uploadSize, '
      'credits: $credits, '
      'arBalance: $arBalance, '
      'turboCredits: $turboCredits, '
      'uploadMethod: $uploadMethod, '
      'isButtonToUploadEnabled: $isButtonToUploadEnabled, '
      '}';
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

class UploadInProgressUsingNewUploader extends UploadState {
  final UploadProgress progress;
  final UploadController controller;
  final double totalProgress;
  final bool isCanceling;
  final Key? equatableBust;
  final UploadMethod uploadMethod;
  final bool containsLargeTurboUpload;

  UploadInProgressUsingNewUploader({
    required this.progress,
    required this.totalProgress,
    required this.controller,
    this.equatableBust,
    this.isCanceling = false,
    required this.uploadMethod,
    required this.containsLargeTurboUpload,
  });

  @override
  List<Object?> get props => [equatableBust];
}

class UploadFailure extends UploadState {
  final UploadErrors error;

  UploadFailure({required this.error});
}

class UploadComplete extends UploadState {}

class UploadWalletMismatch extends UploadState {}

class UploadShowingWarning extends UploadState {
  final UploadWarningReason reason;
  final UploadPlan? uploadPlanForAR;
  final UploadPlan? uploadPlanForTurbo;

  UploadShowingWarning({
    required this.reason,
    this.uploadPlanForAR,
    this.uploadPlanForTurbo,
  });

  @override
  List<Object> get props => [reason];
}

class UploadCanceled extends UploadState {}

class CancelD2NUploadWarning extends UploadState {}

enum UploadWarningReason {
  /// The user is attempting to upload a file that is too large.
  fileTooLarge,
  fileTooLargeOnNonChromeBrowser,
}

enum UploadErrors {
  turboTimeout,
  unknown,
}
