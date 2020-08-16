part of 'drive_detail_bloc.dart';

@immutable
abstract class DriveDetailState {}

class FolderOpening extends DriveDetailState {}

class FolderOpened extends DriveDetailState {
  final Drive openedDrive;
  final FolderWithContents openedFolder;

  FolderOpened({this.openedDrive, this.openedFolder});
}

class DrivePathSegment {
  final String folderId;
  final String folderName;

  DrivePathSegment({this.folderId, this.folderName});
}
