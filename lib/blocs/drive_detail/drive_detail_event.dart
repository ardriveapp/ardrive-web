part of 'drive_detail_bloc.dart';

@immutable
abstract class DriveDetailEvent {}

class OpenDrive extends DriveDetailEvent {
  final String driveId;

  OpenDrive(this.driveId);
}

class OpenedDrive extends DriveDetailEvent {
  final Drive drive;

  OpenedDrive(this.drive);
}

class OpenFolder extends DriveDetailEvent {
  final String folderId;

  OpenFolder(this.folderId);
}

class OpenedFolder extends DriveDetailEvent {
  final FolderEntry openedFolder;

  OpenedFolder(this.openedFolder);
}
