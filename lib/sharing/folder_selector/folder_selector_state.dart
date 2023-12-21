part of 'folder_selector_bloc.dart';

sealed class FolderSelectorState extends Equatable {
  const FolderSelectorState();

  @override
  List<Object> get props => [];
}

final class LoadingDrivesState extends FolderSelectorState {}

final class FolderSelectorInitial extends FolderSelectorState {}

final class SelectingDriveState extends FolderSelectorState {
  final List<Drive> drives;
  final Drive? selectedDrive;

  const SelectingDriveState({required this.drives, this.selectedDrive});

  @override
  List<Object> get props => [drives, selectedDrive ?? ''];
}

final class SelectingFolderState extends FolderSelectorState {
  final List<FolderEntry> folders;
  final FolderEntry? selectedFolder;

  const SelectingFolderState({required this.folders, this.selectedFolder});

  @override
  List<Object> get props => [folders, selectedFolder ?? ''];
}

final class FolderSelectedState extends FolderSelectorState {
  final String folder;
  final String driveId;
  const FolderSelectedState(this.folder, this.driveId);
}
