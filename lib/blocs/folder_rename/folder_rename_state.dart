part of 'folder_rename_cubit.dart';

abstract class FolderRenameState extends Equatable {
  const FolderRenameState();

  @override
  List<Object> get props => [];
}

class FolderRenameInitializing extends FolderRenameState {}

class FolderRenameInitialized extends FolderRenameState {}

class FolderRenameInProgress extends FolderRenameState {}

class FolderRenameSuccess extends FolderRenameState {}
