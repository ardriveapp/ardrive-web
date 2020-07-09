part of 'drive_detail_bloc.dart';

@immutable
abstract class DriveDetailState {}

class DriveDetailFolderOpening extends DriveDetailState {
  final String selectedFolderId;

  DriveDetailFolderOpening({this.selectedFolderId});
}

class DriveDetailFolderOpenSuccess extends DriveDetailState {
  final String selectedFolderId;
  final List<DrivePathSegment> selectedFolderPathSegments;

  final List<Folder> subfolders;
  final List<File> files;

  DriveDetailFolderOpenSuccess(
      {this.selectedFolderId,
      this.selectedFolderPathSegments,
      this.subfolders,
      this.files});
}

class DrivePathSegment {
  final String folderId;
  final String folderName;

  DrivePathSegment({this.folderId, this.folderName});
}
