part of 'create_manifest_cubit.dart';

@immutable
abstract class CreateManifestState extends Equatable {
  @override
  List get props => [];
}

/// Initial state where user begins by selecting a name for the manifest
class CreateManifestInitial extends CreateManifestState {}

/// Name has been selected, user is now selecting which folder to create a manifest of
class CreateManifestFolderLoadSuccess extends CreateManifestState {
  final bool viewingRootFolder;
  final FolderWithContents viewingFolder;

  CreateManifestFolderLoadSuccess({
    required this.viewingRootFolder,
    required this.viewingFolder,
  });

  @override
  List<Object> get props => [viewingRootFolder, viewingFolder];
}

/// User has selected a folder and we are checking for name conflicts
class CreateManifestCheckingForConflicts extends CreateManifestState {
  final FolderEntry parentFolder;

  CreateManifestCheckingForConflicts({required this.parentFolder});

  @override
  List<Object> get props => [parentFolder];
}

/// There is an existing non-manifest FILE or FOLDER entity with a
/// conflicting name. User must re-name the manifest or abort the action
class CreateManifestNameConflict extends CreateManifestState {
  final String conflictingName;
  final FolderEntry parentFolder;

  CreateManifestNameConflict({
    required this.conflictingName,
    required this.parentFolder,
  });

  @override
  List<Object> get props => [conflictingName, parentFolder];
}

/// There is an existing manifest with a conflicting name. Prompt the
/// user to confirm that this is a revision upload or abort the action
class CreateManifestRevisionConfirm extends CreateManifestState {
  final FileID existingManifestFileId;
  final FolderEntry parentFolder;

  CreateManifestRevisionConfirm({
    required this.existingManifestFileId,
    required this.parentFolder,
  });

  @override
  List<Object> get props => [existingManifestFileId, parentFolder];
}

/// Conflicts have been resolved and we will now prepare the manifest transaction
class CreateManifestPreparingManifest extends CreateManifestState {
  final FolderEntry parentFolder;

  CreateManifestPreparingManifest({required this.parentFolder});

  @override
  List<Object> get props => [parentFolder];
}

class CreateManifestUploadReview extends CreateManifestState {
  final int manifestSize;
  final String manifestName;
  final bool folderHasPendingFiles;
  final IOFile manifestFile;
  final bool freeUpload;
  final UploadMethod? uploadMethod;
  final Drive drive;
  final FolderEntry parentFolder;
  final String? existingManifestFileId;
  final bool canUpload;

  CreateManifestUploadReview({
    required this.manifestSize,
    required this.manifestName,
    required this.folderHasPendingFiles,
    required this.manifestFile,
    this.freeUpload = false,
    this.uploadMethod,
    required this.drive,
    required this.parentFolder,
    this.existingManifestFileId,
    this.canUpload = false,
  });

  @override
  List get props => [
        manifestSize,
        manifestName,
        manifestFile,
        folderHasPendingFiles,
        freeUpload,
        uploadMethod,
        drive,
        parentFolder,
        existingManifestFileId,
      ];

  CreateManifestUploadReview copyWith({
    int? manifestSize,
    String? manifestName,
    bool? folderHasPendingFiles,
    IOFile? manifestFile,
    bool? freeUpload,
    UploadMethod? uploadMethod,
    Drive? drive,
    FolderEntry? parentFolder,
    String? existingManifestFileId,
    bool? canUpload,
  }) {
    return CreateManifestUploadReview(
      manifestSize: manifestSize ?? this.manifestSize,
      manifestName: manifestName ?? this.manifestName,
      folderHasPendingFiles:
          folderHasPendingFiles ?? this.folderHasPendingFiles,
      manifestFile: manifestFile ?? this.manifestFile,
      freeUpload: freeUpload ?? this.freeUpload,
      uploadMethod: uploadMethod ?? this.uploadMethod,
      drive: drive ?? this.drive,
      parentFolder: parentFolder ?? this.parentFolder,
      existingManifestFileId:
          existingManifestFileId ?? this.existingManifestFileId,
      canUpload: canUpload ?? this.canUpload,
    );
  }
}

/// User has confirmed the upload and the manifest transaction upload has started
class CreateManifestUploadInProgress extends CreateManifestState {}

/// Private drive has been detected, create manifest must be aborted
class CreateManifestPrivacyMismatch extends CreateManifestState {}

/// Provided wallet does not match the expected wallet, create manifest must be aborted
class CreateManifestWalletMismatch extends CreateManifestState {}

/// Manifest transaction upload has failed
class CreateManifestFailure extends CreateManifestState {}

/// Manifest transaction has been successfully uploaded
class CreateManifestSuccess extends CreateManifestState {}
