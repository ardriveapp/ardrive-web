part of 'ghost_fixer_cubit.dart';

@immutable
abstract class GhostFixerState extends Equatable {
  @override
  List<Object> get props => [];
}

class GhostFixerInitial extends GhostFixerState {}

class GhostFixerRepairInProgress extends GhostFixerState {}

class GhostFixerSuccess extends GhostFixerState {}

class GhostFixerFolderLoadSuccess extends GhostFixerState {
  final bool viewingRootFolder;
  final FolderWithContents viewingFolder;

  /// The id of the folder/file entry being moved.
  final String movingEntryId;

  GhostFixerFolderLoadSuccess({
    required this.viewingRootFolder,
    required this.viewingFolder,
    required this.movingEntryId,
  });

  @override
  List<Object> get props => [viewingRootFolder, viewingFolder, movingEntryId];
}

class GhostFixerNameConflict extends GhostFixerState {
  final String name;
  GhostFixerNameConflict({
    required this.name,
  });
  @override
  List<Object> get props => [name];
}

class GhostFixerFailure extends GhostFixerState {}

class GhostFixerWalletMismatch extends GhostFixerState {}
