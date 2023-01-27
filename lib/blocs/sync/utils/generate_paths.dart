part of 'package:ardrive/blocs/sync/sync_cubit.dart';

/// Generates paths for the folders (and their children) and files provided.
Future<Map<FolderID, GhostFolder>> _generateFsEntryPaths({
  required DriveDao driveDao,
  required String driveId,
  required Map<String, FolderEntriesCompanion> foldersByIdMap,
  required Map<String, FileEntriesCompanion> filesByIdMap,
  required Map<FolderID, GhostFolder> ghostFolders,
}) async {
  final staleFolderTree = <FolderNode>[];
  for (final folder in foldersByIdMap.values) {
    // Get trees of the updated folders and files for path generation.
    final tree = await driveDao.getFolderTree(driveId, folder.id.value);

    // Remove any trees that are a subset of another.
    var newTreeIsSubsetOfExisting = false;
    var newTreeIsSupersetOfExisting = false;
    for (final existingTree in staleFolderTree) {
      if (existingTree.searchForFolder(tree.folder.id) != null) {
        newTreeIsSubsetOfExisting = true;
      } else if (tree.searchForFolder(existingTree.folder.id) != null) {
        staleFolderTree.remove(existingTree);
        staleFolderTree.add(tree);
        newTreeIsSupersetOfExisting = true;
      }
    }

    if (!newTreeIsSubsetOfExisting && !newTreeIsSupersetOfExisting) {
      staleFolderTree.add(tree);
    }
  }

  Future<void> addMissingFolder(String folderId) async {
    ghostFolders.putIfAbsent(
        folderId, () => GhostFolder(folderId: folderId, driveId: driveId));
  }

  Future<void> updateFolderTree(FolderNode node, String parentPath) async {
    final folderId = node.folder.id;
    // If this is the root folder, we should not include its name as part of the path.
    final folderPath = node.folder.parentFolderId != null
        ? '$parentPath/${node.folder.name}'
        : rootPath;

    await driveDao
        .updateFolderById(driveId, folderId)
        .write(FolderEntriesCompanion(path: Value(folderPath)));

    for (final staleFileId in node.files.keys) {
      final filePath = '$folderPath/${node.files[staleFileId]!.name}';

      await driveDao
          .updateFileById(driveId, staleFileId)
          .write(FileEntriesCompanion(path: Value(filePath)));
    }

    for (final staleFolder in node.subfolders) {
      await updateFolderTree(staleFolder, folderPath);
    }
  }

  for (final treeRoot in staleFolderTree) {
    // Get the path of this folder's parent.
    String? parentPath;
    if (treeRoot.folder.parentFolderId == null) {
      parentPath = rootPath;
    } else {
      parentPath = (await driveDao
          .folderById(
              driveId: driveId, folderId: treeRoot.folder.parentFolderId!)
          .map((f) => f.path)
          .getSingleOrNull());
    }
    if (parentPath != null) {
      await updateFolderTree(treeRoot, parentPath);
    } else {
      logSync('Add missing folder: ${treeRoot.folder.name}');
      await addMissingFolder(
        treeRoot.folder.parentFolderId!,
      );
    }
  }

  // Update paths of files whose parent folders were not updated.
  final staleOrphanFiles = filesByIdMap.values
      .where((f) => !foldersByIdMap.containsKey(f.parentFolderId));
  for (final staleOrphanFile in staleOrphanFiles) {
    if (staleOrphanFile.parentFolderId.value.isNotEmpty) {
      final parentPath = await driveDao
          .folderById(
              driveId: driveId, folderId: staleOrphanFile.parentFolderId.value)
          .map((f) => f.path)
          .getSingleOrNull();

      if (parentPath != null) {
        final filePath = '$parentPath/${staleOrphanFile.name.value}';

        await driveDao.writeToFile(FileEntriesCompanion(
            id: staleOrphanFile.id,
            driveId: staleOrphanFile.driveId,
            path: Value(filePath)));
      } else {
        logSync('Add missing folder to file: ${staleOrphanFile.name.value}'
            'folder id: ${staleOrphanFile.id.value}');

        await addMissingFolder(
          staleOrphanFile.parentFolderId.value,
        );
      }
    }
  }
  return ghostFolders;
}
