String fileAndFolderCountsToString({
  required int folderCount,
  required int fileCount,
}) {
  final folderSuffix = folderCount > 1 ? 'folders' : 'folder';
  final fileSuffix = fileCount > 1 ? 'files' : 'file';

  return '$folderCount $folderSuffix, $fileCount $fileSuffix';
}
