part of 'create_manifest_cubit.dart';

@immutable
abstract class CreateManifestState extends Equatable {
  @override
  List<Object> get props => [];
}

class CreateManifestInitial extends CreateManifestState {}

class CreateManifestFolderLoadSuccess extends CreateManifestState {
  final bool viewingRootFolder;
  final FolderWithContents viewingFolder;

  /// The id of the folder/file entry being moved.
  final String movingEntryId;

  CreateManifestFolderLoadSuccess({
    required this.viewingRootFolder,
    required this.viewingFolder,
    required this.movingEntryId,
  });

  @override
  List<Object> get props => [viewingRootFolder, viewingFolder, movingEntryId];
}

class CreateManifestNameConflict extends CreateManifestState {
  final String name;
  CreateManifestNameConflict({
    required this.name,
  });
  @override
  List<Object> get props => [name];
}

class CreateManifestRevisionConfirm extends CreateManifestState {
  final FileID id;
  final FolderEntry parentFolder;
  CreateManifestRevisionConfirm({required this.id, required this.parentFolder});
  @override
  List<Object> get props => [id, parentFolder];
}

class CreateManifestUploadInProgress extends CreateManifestState {}

class CreateManifestFailure extends CreateManifestState {}

class CreateManifestWalletMismatch extends CreateManifestState {}

class CreateManifestSuccess extends CreateManifestState {}
