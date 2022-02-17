part of 'drive_dao.dart';

class FolderNode {
  final FolderEntry folder;
  final List<FolderNode> subfolders;

  /// The file entries this folder, keyed by their file id.
  final Map<FileID, FileEntry> files;

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

  int getRecursiveSubFolderCount() {
    var totalSubFolders = subfolders.length;
    for (var subfolder in subfolders) {
      totalSubFolders += subfolder.getRecursiveSubFolderCount();
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
