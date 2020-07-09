part of 'drive_detail_bloc.dart';

@immutable
abstract class DriveDetailState {}

class DriveOpening extends DriveDetailState {}

class DriveOpened extends DriveDetailState {
  final Drive openedDrive;

  DriveOpened({this.openedDrive});
}

class FolderOpening extends DriveOpened {
  final String selectedFolderId;

  FolderOpening({Drive drive, this.selectedFolderId})
      : super(openedDrive: drive);
}

class FolderOpened extends DriveOpened {
  final FolderWithContents openedFolder;

  FolderOpened({Drive openedDrive, this.openedFolder})
      : super(openedDrive: openedDrive);
}

class DrivePathSegment {
  final String folderId;
  final String folderName;

  DrivePathSegment({this.folderId, this.folderName});
}
