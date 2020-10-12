import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:rxdart/rxdart.dart';
import 'package:test/test.dart';

import '../../utils.dart';

void main() {
  Database db;
  DriveDao driveDao;

  group('DriveDao', () {
    const driveId = 'drive-id';
    const rootFolderId = 'root-folder-id';
    const rootFolderFileCount = 5;
    const nestedFolderIdPrefix = 'nested-folder-id';
    const nestedFolderCount = 5;
    const nestedFolderFileCount = 5;

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
              privacy: DrivePrivacy.public),
        );

        batch.insertAll(
          db.folderEntries,
          [
            FolderEntriesCompanion.insert(
                id: rootFolderId,
                driveId: driveId,
                name: 'drive-name',
                path: ''),
            ...List.generate(
              nestedFolderCount,
              (i) {
                final folderId = '$nestedFolderIdPrefix$i';
                return FolderEntriesCompanion.insert(
                    id: folderId,
                    driveId: driveId,
                    name: folderId,
                    path: '/$folderId');
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
                  ready: true,
                  lastModifiedDate: DateTime.now(),
                );
              },
            )..shuffle(),
            ...List.generate(
              nestedFolderFileCount,
              (i) {
                final fileId = nestedFolderIdPrefix + '0$i';
                return FileEntriesCompanion.insert(
                  id: fileId,
                  driveId: driveId,
                  parentFolderId: nestedFolderIdPrefix,
                  name: fileId,
                  path: '/$nestedFolderIdPrefix' '0' '/$fileId',
                  dataTxId: '',
                  size: 500,
                  ready: true,
                  lastModifiedDate: DateTime.now(),
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
          driveDao.watchFolderContentsAtPath(driveId, '').share();

      await Future.wait([
        expectLater(folderStream.map((f) => f.folder.id), emits(rootFolderId)),
        expectLater(
          folderStream.map((f) => f.subfolders.map((f) => f.name)),
          emits(allOf(hasLength(nestedFolderCount), Sorted())),
        ),
        expectLater(
          folderStream.map((f) => f.files.map((f) => f.id).toList()),
          emits(allOf(hasLength(rootFolderFileCount), Sorted())),
        ),
      ]);

      folderStream = driveDao
          .watchFolderContentsAtPath(driveId, '/$nestedFolderIdPrefix' '0')
          .share();

      await Future.wait([
        expectLater(folderStream.map((f) => f.folder.id),
            emits(nestedFolderIdPrefix + '0')),
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
  });
}

class Sorted extends Matcher {
  Sorted();

  @override
  Description describe(Description description) =>
      description.addDescriptionOf('sorted');

  @override
  Description describeMismatch(dynamic item, Description mismatchDescription,
          Map matchState, bool verbose) =>
      mismatchDescription.add('is not sorted');

  @override
  bool matches(dynamic item, Map matchState) {
    if (item is Iterable<String>) {
      String previousEl;
      for (final element in item) {
        if (previousEl != null && element.compareTo(previousEl) < 0) {
          return false;
        }
        previousEl = element;
      }

      return true;
    }

    return false;
  }
}
