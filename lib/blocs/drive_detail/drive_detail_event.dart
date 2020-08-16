part of 'drive_detail_bloc.dart';

@immutable
abstract class DriveDetailEvent {}

class OpenDrive extends DriveDetailEvent {}

class OpenedDrive extends DriveDetailEvent {
  final Drive drive;

  OpenedDrive(this.drive);
}

class OpenFolder extends DriveDetailEvent {
  final String folderPath;

  OpenFolder(this.folderPath);
}

class OpenedFolder extends DriveDetailEvent {
  final FolderWithContents openedFolder;

  OpenedFolder(this.openedFolder);
}

class NewFolder extends DriveDetailEvent {
  final String folderName;

  NewFolder(this.folderName);
}

class UploadFile extends DriveDetailEvent {
  final FileEntity fileEntity;
  final Uint8List fileStream;

  UploadFile(this.fileEntity, this.fileStream);
}
