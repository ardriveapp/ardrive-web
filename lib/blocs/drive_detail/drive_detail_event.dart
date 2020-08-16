part of 'drive_detail_bloc.dart';

@immutable
abstract class DriveDetailEvent {}

class OpenFolder extends DriveDetailEvent {
  final String folderPath;

  OpenFolder(this.folderPath);
}

class OpenedFolder extends DriveDetailEvent {
  final Drive openedDrive;
  final FolderWithContents openedFolder;

  OpenedFolder(this.openedDrive, this.openedFolder);
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
