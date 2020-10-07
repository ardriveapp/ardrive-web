part of 'drive_detail_cubit.dart';

@immutable
abstract class DriveDetailState extends Equatable {
  @override
  List<Object> get props => [];
}

class FolderLoadInProgress extends DriveDetailState {}

class FolderLoadSuccess extends DriveDetailState {
  final Drive currentDrive;
  final bool hasWritePermissions;

  final FolderWithContents currentFolder;

  FolderLoadSuccess(
      {this.currentDrive, this.hasWritePermissions, this.currentFolder});
}
