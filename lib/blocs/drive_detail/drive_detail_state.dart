part of 'drive_detail_bloc.dart';

@immutable
abstract class DriveDetailState {}

class FolderOpening extends DriveDetailState {}

class FolderOpened extends DriveDetailState {
  final Drive currentDrive;
  final bool hasWritePermissions;

  final FolderWithContents currentFolder;

  FolderOpened(
      {this.currentDrive, this.hasWritePermissions, this.currentFolder});
}

class DrivePathSegment {
  final String folderId;
  final String folderName;

  DrivePathSegment({this.folderId, this.folderName});
}
