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

class UploadReadyToPrepare extends UploadState {
  final UploadParams params;
  final bool isArConnect;

  UploadReadyToPrepare({
    required this.params,
    this.isArConnect = false,
  });

  @override
  List<Object> get props => [params];
}

/// [UploadReadyInitial] means that the upload is ready to be performed and is awaiting for user to proceed to review.
class UploadReadyInitial extends UploadState {
  final UploadPaymentMethodInfo paymentInfo;
  final bool isNextButtonEnabled;
  final bool isDragNDrop;
  final bool uploadIsPublic;
  final int numberOfFiles;

  final UploadParams params;

  final bool isArConnect;

  UploadReadyInitial({
    required this.paymentInfo,
    required this.uploadIsPublic,
    required this.isNextButtonEnabled,
    this.isDragNDrop = false,
    required this.params,
    required this.numberOfFiles,
    required this.isArConnect,
  });

  // copyWith
  UploadReadyInitial copyWith({
    UploadPaymentMethodInfo? paymentInfo,
    UploadMethod? uploadMethod,
    bool? isNextButtonEnabled,
    bool? isDragNDrop,
    bool? uploadIsPublic,
    int? numberOfFiles,
    UploadParams? params,
    bool? isArConnect,
  }) {
    return UploadReadyInitial(
      isArConnect: isArConnect ?? this.isArConnect,
      uploadIsPublic: uploadIsPublic ?? this.uploadIsPublic,
      isDragNDrop: isDragNDrop ?? this.isDragNDrop,
      paymentInfo: paymentInfo ?? this.paymentInfo,
      params: params ?? this.params,
      isNextButtonEnabled: isNextButtonEnabled ?? this.isNextButtonEnabled,
      numberOfFiles: numberOfFiles ?? this.numberOfFiles,
    );
  }

  UploadReadyReview noLicenseReview() {
    return UploadReadyReview(
      readyState: this,
    );
  }

  UploadReadyConfiguringLicense configureLicense({
    required LicenseCategory licenseCategory,
  }) {
    return UploadReadyConfiguringLicense(
      readyState: this,
      licenseCategory: licenseCategory,
    );
  }

  @override
  List<Object?> get props => [
        paymentInfo,
        isNextButtonEnabled,
      ];

  @override
  toString() => 'UploadReadyInitial { paymentInfo: $paymentInfo }';
}

/// [UploadReadyReview] means that the upload is being reviewed by the user and awaiting confirmation.
class UploadReadyReview extends UploadState {
  final UploadReadyInitial readyState;

  UploadReadyReview({
    required this.readyState,
  });

  UploadReadyInitial cancelReview() {
    return readyState;
  }

  @override
  List<Object?> get props => [
        readyState,
      ];

  @override
  toString() => 'UploadReadyReview { paymentInfo: ${readyState.paymentInfo} }';
}

/// [UploadReadyConfiguringLicense] means that the upload is ready to be performed but license is being configured.
class UploadReadyConfiguringLicense extends UploadState {
  final UploadReadyInitial readyState;
  final LicenseCategory licenseCategory;

  UploadReadyConfiguringLicense({
    required this.readyState,
    required this.licenseCategory,
  });

  UploadReadyInitial cancelConfiguring() {
    return readyState;
  }

  UploadReadyReviewWithLicense addLicense({
    required LicenseState licenseState,
  }) {
    return UploadReadyReviewWithLicense(
      readyState: readyState,
      licenseCategory: licenseCategory,
      licenseState: licenseState,
    );
  }

  @override
  List<Object?> get props => [
        readyState,
        licenseCategory,
      ];

  @override
  toString() =>
      'UploadReadyConfiguringLicense { paymentInfo: ${readyState.paymentInfo} }';
}

/// [UploadReadyReviewWithLicense] means that the (licensed) upload is being reviewed by the user and awaiting confirmation.
class UploadReadyReviewWithLicense extends UploadState {
  final UploadReadyInitial readyState;
  final LicenseCategory licenseCategory;
  final LicenseState licenseState;

  UploadReadyReviewWithLicense({
    required this.readyState,
    required this.licenseCategory,
    required this.licenseState,
  });

  UploadReadyConfiguringLicense reconfigureLicense() {
    return UploadReadyConfiguringLicense(
      readyState: readyState,
      licenseCategory: licenseCategory,
    );
  }

  @override
  List<Object?> get props => [
        readyState,
        licenseCategory,
        licenseState,
      ];

  @override
  toString() =>
      'UploadReadyReviewWithLicense { paymentInfo: ${readyState.paymentInfo} }';
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

  UploadInProgressUsingNewUploader({
    required this.progress,
    required this.totalProgress,
    required this.controller,
    this.equatableBust,
    this.isCanceling = false,
    required this.uploadMethod,
  });

  @override
  List<Object?> get props => [equatableBust];
}

class UploadFailure extends UploadState {
  final List<UploadTask>? failedTasks;
  final UploadErrors error;
  final UploadController? controller;

  UploadFailure({this.failedTasks, required this.error, this.controller});
}

class UploadComplete extends UploadState {}

class UploadWalletMismatch extends UploadState {}

class UploadShowingWarning extends UploadState {
  final UploadPlan? uploadPlanForAR;
  final UploadPlan? uploadPlanForTurbo;

  UploadShowingWarning({
    this.uploadPlanForAR,
    this.uploadPlanForTurbo,
  });
}

class UploadCanceled extends UploadState {}

class CancelD2NUploadWarning extends UploadState {}

enum UploadErrors {
  turboTimeout,
  unknown,
}
