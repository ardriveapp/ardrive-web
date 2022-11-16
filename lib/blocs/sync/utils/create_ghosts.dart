part of 'package:ardrive/blocs/sync/sync_cubit.dart';

Future<void> createGhosts({
  required DriveDao driveDao,
  required Map<FolderID, GhostFolder> ghostFolders,
  String? ownerAddress,
}) async {
  final ghostFoldersByDrive =
      <DriveID, Map<FolderID, FolderEntriesCompanion>>{};
  //Finalize missing parent list
  for (final ghostFolder in ghostFolders.values) {
    final folder = await driveDao
        .folderById(
          driveId: ghostFolder.driveId,
          folderId: ghostFolder.folderId,
        )
        .getSingleOrNull();

    final folderExists = folder != null;

    if (folderExists) {
      continue;
    }

    // Add to database
    final drive =
        await driveDao.driveById(driveId: ghostFolder.driveId).getSingle();

    // Don't create ghost folder if the ghost is a missing root folder
    // Or if the drive doesn't belong to the user
    final isReadOnlyDrive = drive.ownerAddress != ownerAddress;
    final isRootFolderGhost = drive.rootFolderId == ghostFolder.folderId;

    if (isReadOnlyDrive || isRootFolderGhost) {
      continue;
    }

    final folderEntry = FolderEntry(
      id: ghostFolder.folderId,
      driveId: drive.id,
      parentFolderId: drive.rootFolderId,
      name: ghostFolder.folderId,
      path: rootPath,
      lastUpdated: DateTime.now(),
      isGhost: true,
      dateCreated: DateTime.now(),
    );
    await driveDao.into(driveDao.folderEntries).insert(folderEntry);
    ghostFoldersByDrive.putIfAbsent(
      drive.id,
      () => {folderEntry.id: folderEntry.toCompanion(false)},
    );
  }
  await Future.wait(
    [
      ...ghostFoldersByDrive.entries.map((entry) => _generateFsEntryPaths(
          driveDao: driveDao,
          driveId: entry.key,
          foldersByIdMap: entry.value,
          filesByIdMap: {})),
    ],
  );
}
