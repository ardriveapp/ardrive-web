part of 'drive_dao.dart';

class FolderNode {
  final FolderEntry? folder;
  final List<FolderNode>? subfolders;

  /// The names of the files in this folder, keyed by their id.
  final Map<String?, String?>? files;

  FolderNode({this.folder, this.subfolders, this.files});

  FolderNode? searchForFolder(String? folderId) {
    if (folder!.id == folderId) return this;

    for (final subfolder in subfolders!) {
      return subfolder.searchForFolder(folderId);
    }

    return null;
  }
}
