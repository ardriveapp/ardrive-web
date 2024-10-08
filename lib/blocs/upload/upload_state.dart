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

class UploadLoadingFiles extends UploadState {}

class UploadLoadingFilesSuccess extends UploadState {}

class UploadPreparationInitialized extends UploadState {
  final bool showLoadingFiles;

  UploadPreparationInitialized({this.showLoadingFiles = false});
}

class UploadSigningInProgress extends UploadState {
  final UploadPlan uploadPlan;
  final bool isArConnect;

  UploadSigningInProgress({required this.uploadPlan, this.isArConnect = false});
  @override
  List<Object> get props => [uploadPlan, isArConnect];
}

class UploadFileConflict extends UploadState {
  final List<String> conflictingFileNames;
  final List<String> conflictingFileNamesForFailedFiles;

  final bool areAllFilesConflicting;

  UploadFileConflict({
    required this.conflictingFileNames,
    required this.areAllFilesConflicting,
    required this.conflictingFileNamesForFailedFiles,
  });

  @override
  List<Object> get props => [conflictingFileNames];
}

class UploadConflictWithFailedFiles extends UploadFileConflict {
  UploadConflictWithFailedFiles({
    required super.conflictingFileNames,
    required super.areAllFilesConflicting,
    super.conflictingFileNamesForFailedFiles = const <String>[],
  });
}

class UploadFolderNameConflict extends UploadFileConflict {
  UploadFolderNameConflict({
    required super.conflictingFileNames,
    required super.areAllFilesConflicting,
    super.conflictingFileNamesForFailedFiles = const <String>[],
  });
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

/// [UploadReady] means that the upload is ready to be performed and is awaiting the user to proceed.
class UploadReady extends UploadState {
  final UploadPaymentMethodInfo paymentInfo;
  final bool isNextButtonEnabled;
  final bool isDragNDrop;
  final bool uploadIsPublic;
  final int numberOfFiles;
  final UploadParams params;
  final bool showArnsCheckbox;
  final bool showArnsNameSelection;
  final bool loadingArNSNames;
  final bool loadingArNSNamesError;
  final bool arnsCheckboxChecked;
  final int totalSize;
  final List<FileEntry> selectedManifests;
  final List<FileEntry> manifestFiles;
  final bool showSettings;

  final bool isArConnect;

  UploadReady({
    required this.paymentInfo,
    required this.uploadIsPublic,
    required this.isNextButtonEnabled,
    this.isDragNDrop = false,
    required this.params,
    required this.numberOfFiles,
    required this.isArConnect,
    required this.showArnsCheckbox,
    required this.showArnsNameSelection,
    this.loadingArNSNames = false,
    this.loadingArNSNamesError = false,
    required this.arnsCheckboxChecked,
    required this.totalSize,
    required this.selectedManifests,
    required this.showSettings,
    required this.manifestFiles,
  });

  // copyWith
  UploadReady copyWith({
    UploadPaymentMethodInfo? paymentInfo,
    UploadMethod? uploadMethod,
    bool? isNextButtonEnabled,
    bool? isDragNDrop,
    bool? uploadIsPublic,
    int? numberOfFiles,
    UploadParams? params,
    bool? isArConnect,
    bool? showSettings,
    bool? showArnsCheckbox,
    bool? showArnsNameSelection,
    bool? loadingArNSNames,
    bool? loadingArNSNamesError,
    bool? arnsCheckboxChecked,
    int? totalSize,
    List<FileEntry>? selectedManifests,
    List<FileEntry>? manifestFiles,
  }) {
    return UploadReady(
      loadingArNSNames: loadingArNSNames ?? this.loadingArNSNames,
      isArConnect: isArConnect ?? this.isArConnect,
      uploadIsPublic: uploadIsPublic ?? this.uploadIsPublic,
      isDragNDrop: isDragNDrop ?? this.isDragNDrop,
      paymentInfo: paymentInfo ?? this.paymentInfo,
      params: params ?? this.params,
      isNextButtonEnabled: isNextButtonEnabled ?? this.isNextButtonEnabled,
      numberOfFiles: numberOfFiles ?? this.numberOfFiles,
      showArnsCheckbox: showArnsCheckbox ?? this.showArnsCheckbox,
      showArnsNameSelection:
          showArnsNameSelection ?? this.showArnsNameSelection,
      loadingArNSNamesError:
          loadingArNSNamesError ?? this.loadingArNSNamesError,
      arnsCheckboxChecked: arnsCheckboxChecked ?? this.arnsCheckboxChecked,
      totalSize: totalSize ?? this.totalSize,
      selectedManifests: selectedManifests ?? this.selectedManifests,
      showSettings: showSettings ?? this.showSettings,
      manifestFiles: manifestFiles ?? this.manifestFiles,
    );
  }

  @override
  List<Object?> get props => [
        paymentInfo,
        isNextButtonEnabled,
        showArnsNameSelection,
        loadingArNSNamesError,
        loadingArNSNames,
        showArnsCheckbox,
        arnsCheckboxChecked,
        showSettings,
        isArConnect,
      ];

  @override
  toString() => 'UploadReady { paymentInfo: $paymentInfo }';
}

class AssigningUndername extends UploadState {
  final ARNSUndername undername;

  AssigningUndername({required this.undername});

  @override
  List<Object?> get props => [undername];
}

/// [UploadConfiguringLicense] means that the upload is ready to be performed but the user is configuring the license.
class UploadConfiguringLicense extends UploadState {
  final UploadReady readyState;
  final LicenseCategory licenseCategory;

  UploadConfiguringLicense({
    required this.readyState,
    required this.licenseCategory,
  });

  @override
  List<Object?> get props => [
        readyState,
        licenseCategory,
      ];

  @override
  toString() =>
      'UploadConfiguringLicense { paymentInfo: ${readyState.paymentInfo} }';
}

class UploadReviewWithArnsName extends UploadState {
  final UploadReady readyState;

  UploadReviewWithArnsName({required this.readyState});
}

/// [UploadReviewWithLicense] means that the upload + license is being reviewed by the user and awaiting confirmation to begin upload.
class UploadReviewWithLicense extends UploadState {
  final UploadReady readyState;
  final LicenseCategory licenseCategory;
  final LicenseState licenseState;

  UploadReviewWithLicense({
    required this.readyState,
    required this.licenseCategory,
    required this.licenseState,
  });

  @override
  List<Object?> get props => [
        readyState,
        licenseCategory,
        licenseState,
        readyState.params.arnsUnderName,
      ];

  @override
  toString() =>
      'UploadReviewWithLicense { paymentInfo: ${readyState.paymentInfo} }';

  UploadReviewWithLicense copyWith({
    UploadReady? readyState,
    LicenseCategory? licenseCategory,
    LicenseState? licenseState,
  }) {
    return UploadReviewWithLicense(
      readyState: readyState ?? this.readyState,
      licenseCategory: licenseCategory ?? this.licenseCategory,
      licenseState: licenseState ?? this.licenseState,
    );
  }
}

class UploadInProgress extends UploadState {
  final UploadProgress progress;
  final UploadController controller;
  final double totalProgress;
  final bool isCanceling;
  final Key? equatableBust;
  final UploadMethod uploadMethod;

  UploadInProgress({
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

class UploadComplete extends UploadState {
  final List<FileEntry> manifestFiles;
  final ARNSRecord? arnsRecord;

  UploadComplete({required this.manifestFiles, this.arnsRecord});
}

class UploadingManifests extends UploadState {
  final List<UploadManifestModel> manifestFiles;
  final int completedCount;

  UploadingManifests({
    required this.manifestFiles,
    required this.completedCount,
  });

  @override
  List<Object?> get props => [manifestFiles, completedCount];
}

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

class EmptyUpload extends UploadState {}

enum UploadErrors {
  turboTimeout,
  unknown,
}

class UploadManifestSelectPaymentMethod extends UploadState {
  final List<UploadFile> files;
  final List<UploadManifestModel> manifestModels;
  final Drive drive;
  final FolderEntry parentFolder;

  UploadManifestSelectPaymentMethod({
    required this.files,
    required this.drive,
    required this.parentFolder,
    required this.manifestModels,
  });
}

class UploadManifestModel extends Equatable {
  final String name;
  final bool isCompleted;
  final bool freeThanksToTurbo;
  final bool isUploading;
  final String? existingManifestFileId;
  final IOFile? file;

  const UploadManifestModel({
    required this.name,
    this.isCompleted = false,
    required this.freeThanksToTurbo,
    this.isUploading = false,
    this.existingManifestFileId,
    this.file,
  });

  UploadManifestModel copyWith({
    bool? isCompleted,
    bool? isUploading,
    String? existingManifestFileId,
    bool? freeThanksToTurbo,
    IOFile? file,
  }) {
    return UploadManifestModel(
      name: name,
      isCompleted: isCompleted ?? this.isCompleted,
      isUploading: isUploading ?? this.isUploading,
      existingManifestFileId:
          existingManifestFileId ?? this.existingManifestFileId,
      freeThanksToTurbo: freeThanksToTurbo ?? this.freeThanksToTurbo,
      file: file ?? this.file,
    );
  }

  @override
  List<Object?> get props => [
        name,
        isCompleted,
        isUploading,
        existingManifestFileId,
        freeThanksToTurbo
      ];
}
//
