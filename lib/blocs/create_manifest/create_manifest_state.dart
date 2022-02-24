part of 'create_manifest_cubit.dart';

@immutable
abstract class CreateManifestState extends Equatable {
  @override
  List<Object> get props => [];
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

/// User selected a folder, but there is an existing non-manifest FILE or FOLDER entity
/// with a conflicting name. User must re-name the manifest or abort the action
class CreateManifestNameConflict extends CreateManifestState {
  final String name;
  final FolderEntry parentFolder;
  CreateManifestNameConflict({required this.name, required this.parentFolder});
  @override
  List<Object> get props => [name, parentFolder];
}

/// User selected a folder, but there is an existing manifest with a conflicting name
/// Prompt the user to confirm that this is a revision upload or abort the action
class CreateManifestRevisionConfirm extends CreateManifestState {
  final FileID id;
  final FolderEntry parentFolder;

  CreateManifestRevisionConfirm({required this.id, required this.parentFolder});
  @override
  List<Object> get props => [id, parentFolder];
}

/// Conflicts have been resolved and we are preparing the manifest transaction
class CreateManifestPreparingManifest extends CreateManifestState {}

/// User does not have enough AR to cover the manifest transaction reward and tip
class CreateManifestInsufficientBalance extends CreateManifestState {}

/// Name conflicts have been resolved, prompt user to confirm price of the upload
class CreateManifestUploadConfirmation extends CreateManifestState {
  final int manifestSize;
  final String manifestName;

  final String arUploadCost;
  final double usdUploadCost;

  final UploadManifestParams uploadManifestParams;

  CreateManifestUploadConfirmation({
    required this.manifestSize,
    required this.manifestName,
    required this.arUploadCost,
    required this.usdUploadCost,
    required this.uploadManifestParams,
  });

  @override
  List<Object> get props => [
        manifestSize,
        manifestName,
        arUploadCost,
        usdUploadCost,
        uploadManifestParams,
      ];
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
