import 'package:ardrive/models/models.dart';
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
    test('watchFolder() with root path (' ') returns root folder', () async {
      final folderStream =
          driveDao.watchFolderContents(driveId, folderPath: '');

      await Future.wait([
        expectLater(folderStream.map((f) => f.folder!.id), emits(rootFolderId)),
      ]);
    });
    test('watchFolder() returns correct number of files in root folder',
        () async {
      final folderStream =
          driveDao.watchFolderContents(driveId, folderPath: '');

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
      final folderStream =
          driveDao.watchFolderContents(driveId, folderPath: '');

      await Future.wait([
        expectLater(
          folderStream.map((f) => f.subfolders.map((f) => f.name)),
          // emptyNestedFolders + nestedFolder
          emits(allOf(hasLength(emptyNestedFolderCount + 1), Sorted())),
        ),
      ]);
    });

    test('watchFolder() with subfolder path returns correct subfolder',
        () async {
      final folderStream = driveDao.watchFolderContents(driveId,
          folderPath: '/$emptyNestedFolderIdPrefix' '0');

      await Future.wait([
        expectLater(folderStream.map((f) => f.folder!.id),
            emits(emptyNestedFolderIdPrefix + '0')),
      ]);
    });
    test('watchFolder() returns correct folders inside empty folder', () async {
      final folderStream = driveDao.watchFolderContents(driveId,
          folderPath: '/$emptyNestedFolderIdPrefix' '0');

      await Future.wait([
        expectLater(
          folderStream.map((f) => f.subfolders.map((f) => f.id)),
          emits(hasLength(0)),
        ),
      ]);
    });
    test('watchFolder() returns correct files inside empty folder', () async {
      final folderStream = driveDao.watchFolderContents(driveId,
          folderPath: '/$emptyNestedFolderIdPrefix' '0');

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

    test('getRecursiveFolderCount returns the correct folder count', () async {
      final treeRoot = await driveDao.getFolderTree(driveId, rootFolderId);

      expect(
        treeRoot.getRecursiveFolderCount(),
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
  });
}
