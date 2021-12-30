import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:moor/moor.dart';
import 'package:rxdart/rxdart.dart';
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
      await db.batch((batch) {
        batch.insert(
          db.drives,
          DrivesCompanion.insert(
            id: driveId,
            rootFolderId: rootFolderId,
            ownerAddress: 'owner-address',
            name: 'drive-name',
            privacy: DrivePrivacy.public,
          ),
        );

        batch.insertAll(
          db.folderEntries,
          [
            FolderEntriesCompanion.insert(
                id: rootFolderId,
                driveId: driveId,
                name: 'drive-name',
                path: ''),
            FolderEntriesCompanion.insert(
                id: nestedFolderId,
                driveId: driveId,
                parentFolderId: Value(rootFolderId),
                name: nestedFolderId,
                path: '/$nestedFolderId'),
            ...List.generate(
              emptyNestedFolderCount,
              (i) {
                final folderId = '$emptyNestedFolderIdPrefix$i';
                return FolderEntriesCompanion.insert(
                  id: folderId,
                  driveId: driveId,
                  parentFolderId: Value(rootFolderId),
                  name: folderId,
                  path: '/$folderId',
                );
              },
            )..shuffle(),
          ],
        );

        batch.insertAll(
          db.fileEntries,
          [
            ...List.generate(
              rootFolderFileCount,
              (i) {
                final fileId = '$rootFolderId$i';
                return FileEntriesCompanion.insert(
                  id: fileId,
                  driveId: driveId,
                  parentFolderId: rootFolderId,
                  name: fileId,
                  path: '/$fileId',
                  dataTxId: '',
                  size: 500,
                  lastModifiedDate: DateTime.now(),
                  dataContentType: Value(''),
                );
              },
            )..shuffle(),
            ...List.generate(
              nestedFolderFileCount,
              (i) {
                final fileId = '$nestedFolderId$i';
                return FileEntriesCompanion.insert(
                  id: fileId,
                  driveId: driveId,
                  parentFolderId: nestedFolderId,
                  name: fileId,
                  path: '/$nestedFolderId/$fileId',
                  dataTxId: '',
                  size: 500,
                  lastModifiedDate: DateTime.now(),
                  dataContentType: Value(''),
                );
              },
            )..shuffle(),
          ],
        );
      });
    });

    tearDown(() async {
      await db.close();
    });

    test('watchFolder() returns correct folder contents', () async {
      var folderStream =
          driveDao.watchFolderContents(driveId, folderPath: '').share();

      await Future.wait([
        expectLater(folderStream.map((f) => f.folder!.id), emits(rootFolderId)),
        expectLater(
          folderStream.map((f) => f.subfolders.map((f) => f.name)),
          emits(allOf(hasLength(emptyNestedFolderCount), Sorted())),
        ),
        expectLater(
          folderStream.map((f) => f.files.map((f) => f.id).toList()),
          emits(allOf(hasLength(rootFolderFileCount), Sorted())),
        ),
      ]);

      folderStream = driveDao
          .watchFolderContents(driveId,
              folderPath: '/$emptyNestedFolderIdPrefix' '0')
          .share();

      await Future.wait([
        expectLater(folderStream.map((f) => f.folder!.id),
            emits(emptyNestedFolderIdPrefix + '0')),
        expectLater(
          folderStream.map((f) => f.subfolders.map((f) => f.id)),
          emits(hasLength(0)),
        ),
        expectLater(
          folderStream.map((f) => f.files.map((f) => f.name).toList()),
          emits(allOf(hasLength(nestedFolderFileCount), Sorted())),
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
  });
}
