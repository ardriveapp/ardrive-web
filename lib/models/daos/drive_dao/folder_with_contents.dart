part of 'drive_dao.dart';

class FolderWithContents extends Equatable {
  final FolderEntry folder;
  final List<FolderEntry> subfolders;
  final List<FileEntry> files;

  FolderWithContents({this.folder, this.subfolders, this.files});

  @override
  List<Object> get props => [folder, subfolders, files];
}
