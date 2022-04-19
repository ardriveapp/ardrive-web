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
      final foundFolder = subfolder.searchForFolder(folderId);

      if (foundFolder != null) {
        return foundFolder;
      }
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
      totalFiles += subfolder.getRecursiveFileSize();
    }
    return totalFiles;
  }

  int getRecursiveFileSize() {
    var totalSize = files.isNotEmpty
        ? files.values.map((file) => file.size).reduce(
              (value, fileSize) => value + fileSize,
            )
        : 0;
    for (var subfolder in subfolders) {
      totalSize += subfolder.getRecursiveFileCount();
    }
    return totalSize;
  }

  // TODO: maxDepth slider in story ticket PE-1069
  List<FileEntry> getRecursiveFiles(/*{maxDepth = 2000000}*/) {
    // if (maxDepth == -1) {
    //   return [];
    // }

    final totalFiles = files.values.toList();
    for (final subfolder in subfolders) {
      totalFiles
          .addAll(subfolder.getRecursiveFiles(/*maxDepth: maxDepth - 1*/));
    }
    return totalFiles;
  }

  /// Returns true when the folder node does not contain any file entities
  bool isEmpty() {
    return getRecursiveFileCount() == 0;
  }
}
