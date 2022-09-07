@Tags(['broken'])

import 'package:ardrive/models/models.dart';
import 'package:test/test.dart';

import '../../test_utils/utils.dart';

void main() {
  late Database db;
  late DriveDao driveDao;

  group('DriveDao', () {
    const driveId = 'drive-id';
    const rootPath = '';
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
    test("watchFolder() with root path ('') returns root folder", () async {
      final folderStream =
          driveDao.watchFolderContents(driveId, folderPath: rootPath);

      await Future.wait([
        expectLater(folderStream.map((f) => f.folder.id), emits(rootFolderId)),
      ]);
    });
    test('watchFolder() returns correct number of files in root folder',
        () async {
      final folderStream =
          driveDao.watchFolderContents(driveId, folderPath: rootPath);

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
          driveDao.watchFolderContents(driveId, folderPath: rootPath);

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
        expectLater(folderStream.map((f) => f.folder.id),
            emits('${emptyNestedFolderIdPrefix}0')),
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
        expect(file.path, equals(expectedTreeResults[i][1]));
      }
    });

    //   test('getRecursiveFiles with a maxDepth of 0 returns just the files in the root folder',
    //       () async {
    //     final treeRoot = await driveDao.getFolderTree(driveId, rootFolderId);
    //     final filesInFolderTree = treeRoot.getRecursiveFiles(maxDepth: 1);

    //     expect(filesInFolderTree.length, equals(5));
    //     for (var i = 0; i < filesInFolderTree.length; i++) {
    //       final file = filesInFolderTree[i];
    //       expect(file.id, equals(expectedTreeResults[i][0]));
    //       expect(file.path, equals(expectedTreeResults[i][1]));
    //     }
    //   });

    //   test('getRecursiveFiles with a maxDepth of -1 returns no files', () async {
    //     final treeRoot = await driveDao.getFolderTree(driveId, rootFolderId);
    //     final filesInFolderTree = treeRoot.getRecursiveFiles(maxDepth: -1);

    //     expect(filesInFolderTree.length, equals(0));
    //   });
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
