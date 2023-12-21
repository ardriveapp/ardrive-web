part of 'folder_selector_bloc.dart';

sealed class FolderSelectorEvent extends Equatable {
  const FolderSelectorEvent();

  @override
  List<Object> get props => [];
}

final class LoadDrivesEvent extends FolderSelectorEvent {}

final class SelectDriveEvent extends FolderSelectorEvent {
  final Drive drive;

  const SelectDriveEvent(this.drive);

  @override
  List<Object> get props => [drive];
}

final class ConfirmDriveEvent extends FolderSelectorEvent {
  final Drive drive;

  const ConfirmDriveEvent(this.drive);

  @override
  List<Object> get props => [drive];
}

final class ConfirmFolderEvent extends FolderSelectorEvent {
  final FolderEntry folder;

  const ConfirmFolderEvent(this.folder);

  @override
  List<Object> get props => [folder];
}

final class SelectFolderEvent extends FolderSelectorEvent {
  final FolderEntry folder;

  const SelectFolderEvent(this.folder);

  @override
  List<Object> get props => [folder];
}
