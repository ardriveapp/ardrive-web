import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:test/test.dart';

import '../../test_utils/utils.dart';

void main() {
  late Database db;
  late DriveDao driveDao;

  group('DriveDao', () {
    const driveId = 'drive-id';
    const rootFolderId = 'root-folder-id';
    const rootFolderFileCount = 5;

    const nestedFolderId = 'nested-folder-id';
    const nestedFolderFileCount = 5;

    const emptyNestedFolderIdPrefix = 'empty-nested-folder-id';
    const emptyNestedFolderCount = 5;

    setUp(() async {
      db = getTestDb();
      driveDao = db.driveDao;

      // Setup mock drive.
      await addTestFilesToDb(
        db,
        driveId: driveId,
        rootFolderId: rootFolderId,
        nestedFolderId: nestedFolderId,
        emptyNestedFolderCount: emptyNestedFolderCount,
        emptyNestedFolderIdPrefix: emptyNestedFolderIdPrefix,
        rootFolderFileCount: rootFolderFileCount,
        nestedFolderFileCount: nestedFolderFileCount,
      );
    });

    tearDown(() async {
      await db.close();
    });
    // Any empty string is a root path
    test(
        'watchFolder() with root path (no folderId provided) returns root folder',
        () async {
      final folderStream = driveDao.watchFolderContents(
        driveId,
      );

      await Future.wait([
        expectLater(folderStream.map((f) => f.folder.id), emits(rootFolderId)),
      ]);
    });
    test('watchFolder() returns correcta number of files in root folder',
        () async {
      final folderStream = driveDao.watchFolderContents(
        driveId,
        folderId: rootFolderId,
      );

      await Future.wait([
        expectLater(
          folderStream.map((f) {
            return f.files.map((f) => f.id);
          }),
          emits(allOf(hasLength(rootFolderFileCount), Sorted())),
        ),
      ]);
    });
    test('watchFolder() returns correct number of folders in root folder',
        () async {
      final folderStream = driveDao.watchFolderContents(
        driveId,
        folderId: rootFolderId,
      );

      await Future.wait([
        expectLater(
          folderStream.map((f) => f.subfolders.map((f) => f.name)),
          // emptyNestedFolders + nestedFolder
          emits(allOf(hasLength(emptyNestedFolderCount + 1), Sorted())),
        ),
      ]);
    });

    test('watchFolder() with subfolder id returns correct subfolder', () async {
      final folderStream = driveDao.watchFolderContents(
        driveId,
        folderId: '${emptyNestedFolderIdPrefix}0',
      );

      await Future.wait([
        expectLater(folderStream.map((f) => f.folder.id),
            emits('${emptyNestedFolderIdPrefix}0')),
      ]);
    });
    test('watchFolder() returns correct folders inside empty folder', () async {
      final folderStream = driveDao.watchFolderContents(
        driveId,
        folderId: '${emptyNestedFolderIdPrefix}0',
      );

      await Future.wait([
        expectLater(
          folderStream.map((f) => f.subfolders.map((f) => f.id)),
          emits(hasLength(0)),
        ),
      ]);
    });
    test('watchFolder() returns correct files inside empty folder', () async {
      final folderStream = driveDao.watchFolderContents(
        driveId,
        folderId: '${emptyNestedFolderIdPrefix}0',
      );

      await Future.wait([
        expectLater(
          folderStream.map((f) => f.files.map((f) => f.id)),
          emits(hasLength(0)),
        ),
      ]);
    });

    test('getFolderTree() constructs tree correctly', () async {
      final treeRoot = await driveDao.getFolderTree(driveId, rootFolderId);

      expect(treeRoot.folder.id, equals(rootFolderId));
      expect(treeRoot.files.length, equals(rootFolderFileCount));

      final nestedSubfolderFileCount = treeRoot.subfolders
          .where((f) => f.folder.id == nestedFolderId)
          .single
          .files
          .length;
      expect(nestedSubfolderFileCount, equals(nestedSubfolderFileCount));

      final emptySubfolders = treeRoot.subfolders
          .where((f) => f.folder.id.startsWith(emptyNestedFolderIdPrefix));
      expect(emptySubfolders.map((f) => f.subfolders.length).toList(),
          everyElement(equals(0)));
      expect(emptySubfolders.map((f) => f.files.length).toList(),
          everyElement(equals(0)));
    });

    test('getRecursiveSubFolderCount returns the correct folder count',
        () async {
      final treeRoot = await driveDao.getFolderTree(driveId, rootFolderId);

      expect(
        treeRoot.getRecursiveSubFolderCount(),
        // 5 empty nested folders and one nested folder with files
        equals(emptyNestedFolderCount + 1),
      );
    });

    test('getRecursiveFileCount returns the correct file count', () async {
      final treeRoot = await driveDao.getFolderTree(driveId, rootFolderId);

      expect(
        treeRoot.getRecursiveFileCount(),
        equals(rootFolderFileCount + nestedFolderFileCount),
      );
    });

    test('getRecursiveFiles returns all the correct files', () async {
      final treeRoot = await driveDao.getFolderTree(driveId, rootFolderId);
      final filesInFolderTree = treeRoot.getRecursiveFiles();

      expect(filesInFolderTree.length, equals(10));
      for (var i = 0; i < filesInFolderTree.length; i++) {
        final file = filesInFolderTree[i];
        expect(file.id, equals(expectedTreeResults[i][0]));
      }
    });
  });

  group('DriveDao.writeFileEntity', () {
    setUp(() {
      db = getTestDb();
      driveDao = db.driveDao;
    });

    tearDown(() async {
      await db.close();
    });

    FileEntity version({
      required int size,
      required DateTime createdAt,
    }) =>
        FileEntity(
          id: 'file-id',
          driveId: 'drive-id',
          parentFolderId: 'folder-id',
          name: 'notes.txt',
          dataTxId: 'data-tx-$size',
          size: size,
          lastModifiedDate: DateTime.utc(2026, 1, 1),
          dataContentType: 'text/plain',
        )..createdAt = createdAt;

    // A new version uploaded on this device moves the date the explorer and
    // the details panel show, as syncing that version would.
    test('dates a new version from its revision, and keeps the first date',
        () async {
      final first = DateTime.utc(2026, 10, 20, 1, 44, 47);
      final second = DateTime.utc(2026, 10, 20, 1, 46, 35);

      await driveDao.writeFileEntity(version(size: 640, createdAt: first));
      final created =
          (await driveDao.fileById(fileId: 'file-id').getSingle()).dateCreated;

      await driveDao.writeFileEntity(version(size: 918, createdAt: second));
      final file = await driveDao.fileById(fileId: 'file-id').getSingle();

      expect(file.size, 918);
      expect(file.lastUpdated.toUtc(), second);
      expect(file.dateCreated, created);
    });
  });

  /// A drive row whose `rootFolderId` has no folder row cannot be opened:
  /// `watchFolderContents` filters the absent folder out and its stream then
  /// never emits, so the explorer sits on a spinner nothing retries. Every path
  /// that writes a drive must therefore also leave a root folder behind.
  group('DriveDao root folder guarantee', () {
    const otherDriveId = 'placeholder-drive-id';
    const otherRootFolderId = 'placeholder-root-folder-id';
    const driveName = 'Placeholder Drive';
    const ownerAddress = 'owner-address';

    DriveEntity driveEntity({String name = driveName}) => DriveEntity(
          id: otherDriveId,
          name: name,
          rootFolderId: otherRootFolderId,
          privacy: DrivePrivacyTag.public,
          authMode: DriveAuthModeTag.none,
        )..ownerAddress = ownerAddress;

    setUp(() async {
      db = getTestDb();
      driveDao = db.driveDao;
    });

    tearDown(() async {
      await db.close();
    });

    test('updateUserDrives() writes a root folder the drive can be opened from',
        () async {
      await driveDao.updateUserDrives({driveEntity(): null}, null);

      final rootFolder = await driveDao
          .folderById(folderId: otherRootFolderId)
          .getSingleOrNull();

      expect(rootFolder, isNotNull);
      expect(rootFolder!.driveId, equals(otherDriveId));

      // The point of the row: the drive mounts instead of hanging.
      await expectLater(
        driveDao.watchFolderContents(otherDriveId).map((f) => f.folder.id),
        emits(otherRootFolderId),
      );
    });

    test('updateUserDrives() does not overwrite an already synced root folder',
        () async {
      await driveDao.updateUserDrives({driveEntity(): null}, null);

      // The real metadata lands, renaming the root folder.
      await driveDao.updateFolderEntries([
        FolderEntriesCompanion.insert(
          id: otherRootFolderId,
          driveId: otherDriveId,
          name: 'Real Root Name',
          path: '',
        ),
      ]);

      // A later sync re-runs the same insert.
      await driveDao.updateUserDrives({driveEntity(): null}, null);

      final rootFolder =
          await driveDao.folderById(folderId: otherRootFolderId).getSingle();

      expect(rootFolder.name, equals('Real Root Name'));
    });

    test('root folder placeholder is not marked as a ghost', () async {
      await driveDao.updateUserDrives({driveEntity(): null}, null);

      final rootFolder =
          await driveDao.folderById(folderId: otherRootFolderId).getSingle();

      // `FolderRevisionsCompanion.toEntryCompanion` omits `isGhost`, and the
      // upsert that lands real metadata leaves absent columns alone - so a
      // placeholder marked as a ghost would stay one forever.
      expect(rootFolder.isGhost, isFalse);
      expect(rootFolder.parentFolderId, isNull);
    });

    /// What tells "genuinely empty" apart from "never synced". A drive created
    /// in-app writes a root folder revision at creation time, and sync writes
    /// one when the real metadata lands; a drive merely discovered by
    /// `updateUserDrives` has only the placeholder until then. Claiming a drive
    /// is empty on weaker evidence reads to the user as data loss.
    test('a discovered drive has no root folder revision until one syncs',
        () async {
      await driveDao.updateUserDrives({driveEntity(): null}, null);

      final beforeSync = await driveDao
          .latestFolderRevisionByFolderId(
            driveId: otherDriveId,
            folderId: otherRootFolderId,
          )
          .getSingleOrNull();

      expect(beforeSync, isNull,
          reason: 'the placeholder must not read as synced metadata');

      // lastBlockHeight cannot stand in for this: it defaults to 0, so it
      // cannot tell a freshly created empty drive from an unsynced one.
      final drive = await driveDao.driveById(driveId: otherDriveId).getSingle();
      expect(drive.lastBlockHeight, equals(0));

      await driveDao.insertFolderRevision(
        FolderRevisionsCompanion.insert(
          folderId: otherRootFolderId,
          driveId: otherDriveId,
          name: 'Real Root Name',
          metadataTxId: 'metadata-tx-id',
          action: RevisionAction.create,
        ),
      );

      final afterSync = await driveDao
          .latestFolderRevisionByFolderId(
            driveId: otherDriveId,
            folderId: otherRootFolderId,
          )
          .getSingleOrNull();

      expect(afterSync, isNotNull);
    });

    test('writeDriveEntity() writes a root folder too', () async {
      await driveDao.writeDriveEntity(name: driveName, entity: driveEntity());

      final rootFolder = await driveDao
          .folderById(folderId: otherRootFolderId)
          .getSingleOrNull();

      expect(rootFolder, isNotNull);
      expect(rootFolder!.name, equals(driveName));
    });
  });

  /// The drive list reads each drive's newest revision, so the time on it is
  /// when the drive last changed. "Date created" showed that: a renamed drive
  /// was dated from the rename.
  group('DriveDao drive creation date', () {
    const driveId = 'dated-drive-id';
    final created = DateTime(2025, 1, 1);
    final renamed = DateTime(2026, 3, 1);
    final hidden = DateTime(2026, 9, 1);

    DriveEntity newest({required DateTime at, String name = 'Pics'}) =>
        DriveEntity(
          id: driveId,
          name: name,
          rootFolderId: 'dated-root-id',
          privacy: DrivePrivacyTag.public,
          authMode: DriveAuthModeTag.none,
        )
          ..ownerAddress = 'owner-address'
          ..createdAt = at;

    Future<Drive> stored() => driveDao.driveById(driveId: driveId).getSingle();

    setUp(() {
      db = getTestDb();
      driveDao = db.driveDao;
    });

    tearDown(() => db.close());

    test('dates a drive from its creation, not its newest revision', () async {
      await driveDao.updateUserDrives(
        {newest(at: renamed): null},
        null,
        creationTimes: {driveId: created},
      );

      final drive = await stored();
      expect(drive.dateCreated, created);
      expect(drive.lastUpdated, renamed);
    });

    test('keeps the creation date when a later pass does not know it',
        () async {
      await driveDao.updateUserDrives(
        {newest(at: renamed): null},
        null,
        creationTimes: {driveId: created},
      );

      await driveDao.updateUserDrives({newest(at: hidden): null}, null);

      final drive = await stored();
      expect(drive.dateCreated, created);
      expect(drive.lastUpdated, hidden);
    });

    /// Drives already stored carry the newest revision's date. The next time
    /// the drive list is read they are put right.
    test('repairs a creation date an earlier pass got wrong', () async {
      await driveDao.updateUserDrives({newest(at: renamed): null}, null);
      expect((await stored()).dateCreated, renamed);

      await driveDao.updateUserDrives(
        {newest(at: renamed): null},
        null,
        creationTimes: {driveId: created},
      );

      expect((await stored()).dateCreated, created);
    });

    test('a re-attach keeps the creation date', () async {
      await driveDao.updateUserDrives(
        {newest(at: renamed): null},
        null,
        creationTimes: {driveId: created},
      );

      await driveDao.writeDriveEntity(
        name: 'Pics',
        entity: newest(at: hidden),
      );

      expect((await stored()).dateCreated, created);
    });
  });
}

/// Expected entity IDs and paths from mocked DB setup
final expectedTreeResults = [
  ['root-folder-id4', '/root-folder-id4'],
  ['root-folder-id2', '/root-folder-id2'],
  ['root-folder-id3', '/root-folder-id3'],
  ['root-folder-id1', '/root-folder-id1'],
  ['root-folder-id0', '/root-folder-id0'],
  ['nested-folder-id4', '/nested-folder-id/nested-folder-id4'],
  ['nested-folder-id2', '/nested-folder-id/nested-folder-id2'],
  ['nested-folder-id3', '/nested-folder-id/nested-folder-id3'],
  ['nested-folder-id1', '/nested-folder-id/nested-folder-id1'],
  ['nested-folder-id0', '/nested-folder-id/nested-folder-id0'],
];
