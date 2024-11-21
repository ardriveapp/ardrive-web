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
  final List<UploadManifestModel> manifestFiles;
  final List<ManifestSelection> selectedManifestSelections;
  final bool showSettings;
  final bool canShowSettings;
  final List<ANTRecord> arnsRecords;

  final bool isArConnect;
  final bool showReviewButtonText;
  final bool shouldShowCustomManifestCheckbox;
  final bool uploadFileAsCustomManifest;

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
    required this.showSettings,
    required this.canShowSettings,
    required this.manifestFiles,
    required this.arnsRecords,
    required this.showReviewButtonText,
    required this.selectedManifestSelections,
    required this.shouldShowCustomManifestCheckbox,
    required this.uploadFileAsCustomManifest,
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
    List<UploadManifestModel>? manifestFiles,
    bool? canShowSettings,
    List<ANTRecord>? arnsRecords,
    bool? showReviewButtonText,
    List<ManifestSelection>? selectedManifestSelections,
    bool? shouldShowCustomManifestCheckbox,
    bool? uploadFileAsCustomManifest,
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
      showSettings: showSettings ?? this.showSettings,
      manifestFiles: manifestFiles ?? this.manifestFiles,
      canShowSettings: canShowSettings ?? this.canShowSettings,
      arnsRecords: arnsRecords ?? this.arnsRecords,
      showReviewButtonText: showReviewButtonText ?? this.showReviewButtonText,
      selectedManifestSelections:
          selectedManifestSelections ?? this.selectedManifestSelections,
      shouldShowCustomManifestCheckbox: shouldShowCustomManifestCheckbox ??
          this.shouldShowCustomManifestCheckbox,
      uploadFileAsCustomManifest:
          uploadFileAsCustomManifest ?? this.uploadFileAsCustomManifest,
    );
  }

  @override
  List<Object?> get props => [UniqueKey()];

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

class UploadReview extends UploadState {
  final UploadReady readyState;

  UploadReview({required this.readyState});
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
  final ARNSRecord? arnsRecord;

  UploadComplete({this.arnsRecord});
}

class UploadingManifests extends UploadState {
  final List<UploadManifestModel> manifestFiles;
  final int completedCount;

  UploadingManifests({
    required this.manifestFiles,
    required this.completedCount,
  });

  @override
  List<Object?> get props => [UniqueKey()];
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
  final FileEntry entry;
  final bool isCompleted;
  final bool isAssigningUndername;
  final bool freeThanksToTurbo;
  final bool isUploading;
  final String existingManifestFileId;
  final IOFile? file;
  final ARNSUndername? undername;
  final ANTRecord? antRecord;
  final bool selectionExpanded;

  const UploadManifestModel({
    required this.entry,
    this.isCompleted = false,
    required this.freeThanksToTurbo,
    this.isUploading = false,
    required this.existingManifestFileId,
    this.file,
    this.undername,
    this.antRecord,
    this.isAssigningUndername = false,
    this.selectionExpanded = false,
  });

  UploadManifestModel copyWith({
    bool? isCompleted,
    bool? isUploading,
    String? existingManifestFileId,
    bool? freeThanksToTurbo,
    IOFile? file,
    ARNSUndername? undername,
    ANTRecord? antRecord,
    bool? isAssigningUndername,
    FileEntry? entry,
    bool? selectionExpanded,
  }) {
    return UploadManifestModel(
      entry: entry ?? this.entry,
      isCompleted: isCompleted ?? this.isCompleted,
      isUploading: isUploading ?? this.isUploading,
      existingManifestFileId:
          existingManifestFileId ?? this.existingManifestFileId,
      freeThanksToTurbo: freeThanksToTurbo ?? this.freeThanksToTurbo,
      file: file ?? this.file,
      undername: undername ?? this.undername,
      antRecord: antRecord ?? this.antRecord,
      isAssigningUndername: isAssigningUndername ?? this.isAssigningUndername,
      selectionExpanded: selectionExpanded ?? this.selectionExpanded,
    );
  }

  @override
  List<Object?> get props => [
        entry,
        isCompleted,
        isUploading,
        existingManifestFileId,
        freeThanksToTurbo,
        isAssigningUndername,
        antRecord,
        undername,
        file,
      ];
}

//
class UploadLoadingFolders extends UploadState {}
