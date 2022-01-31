part of 'drive_dao.dart';

class FolderNode {
  final FolderEntry folder;
  final List<FolderNode> subfolders;

  /// The names of the files in this folder, keyed by their id.
  final Map<String, String> files;

  FolderNode({
    required this.folder,
    required this.subfolders,
    required this.files,
  });

  FolderNode? searchForFolder(String folderId) {
    if (folder.id == folderId) return this;
    for (final subfolder in subfolders) {
      return subfolder.searchForFolder(folderId);
    }
    return null;
  }

  int getRecursiveFolderCount() {
    var totalSubFolders = subfolders.length;
    for (var subfolder in subfolders) {
      totalSubFolders += subfolder.getRecursiveFolderCount();
    }
    return totalSubFolders;
  }

  int getRecursiveFileCount() {
    var totalFiles = files.length;
    for (var subfolder in subfolders) {
      totalFiles += subfolder.getRecursiveFileCount();
    }
    return totalFiles;
  }
}
