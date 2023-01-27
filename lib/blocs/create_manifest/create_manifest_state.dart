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

/// User does not have enough AR to cover the manifest transaction reward and tip, create manifest must be aborted
class CreateManifestInsufficientBalance extends CreateManifestState {
  final String walletBalance;
  final String totalCost;

  CreateManifestInsufficientBalance({
    required this.walletBalance,
    required this.totalCost,
  });

  @override
  List<Object> get props => [walletBalance, totalCost];
}

/// Manifest transaction is prepared, prompt user to confirm price of the upload
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

/// Manifest transaction is prepared, prompt user to confirm price of the upload
class CreateManifestTurboUploadConfirmation extends CreateManifestState {
  final int manifestSize;
  final String manifestName;
  final List<DataItem> manifestDataItems;
  final Future<void> Function() addManifestToDatabase;

  CreateManifestTurboUploadConfirmation({
    required this.manifestSize,
    required this.manifestName,
    required this.manifestDataItems,
    required this.addManifestToDatabase,
  });

  @override
  List<Object> get props => [
        manifestSize,
        manifestName,
        manifestDataItems,
        addManifestToDatabase,
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
