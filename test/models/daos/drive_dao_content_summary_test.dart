import 'package:ardrive/models/models.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:drift/drift.dart';
import 'package:test/test.dart';

import '../../test_utils/utils.dart';

/// The two local reads the drives list is built on.
///
/// They are the foundation of the page: get either wrong and every row lies in
/// a way nothing else in the app would notice, because nothing else asks the
/// database these questions.
void main() {
  late Database db;
  late DriveDao driveDao;

  setUp(() {
    db = getTestDb();
    driveDao = db.driveDao;
  });

  tearDown(() async => db.close());

  Future<void> addDrive(String id) => db.into(db.drives).insert(
        DrivesCompanion.insert(
          id: id,
          rootFolderId: '$id-root',
          ownerAddress: 'owner',
          name: id,
          privacy: DrivePrivacyTag.public,
        ),
      );

  Future<void> addFile(
    String driveId,
    String fileId, {
    required int size,
    bool isHidden = false,
  }) =>
      db.into(db.fileEntries).insert(
            FileEntriesCompanion.insert(
              id: fileId,
              driveId: driveId,
              parentFolderId: '$driveId-root',
              name: fileId,
              dataTxId: '$fileId-tx',
              size: size,
              lastModifiedDate: DateTime(2024, 1, 1),
              path: '',
              isHidden: Value(isHidden),
            ),
          );

  group('driveContentSummaries', () {
    test('is empty when nothing has been synced', () async {
      await addDrive('drive-a');

      expect(await driveDao.driveContentSummaries(), isEmpty);
    });

    test('counts the files of each drive separately', () async {
      await addDrive('drive-a');
      await addDrive('drive-b');

      await addFile('drive-a', 'a1', size: 100);
      await addFile('drive-a', 'a2', size: 250);
      await addFile('drive-b', 'b1', size: 7);

      final summaries = await driveDao.driveContentSummaries();

      expect(summaries['drive-a']!.itemCount, 2);
      expect(summaries['drive-b']!.itemCount, 1);
    });

    test('sums the sizes of each drive separately', () async {
      await addDrive('drive-a');
      await addDrive('drive-b');

      await addFile('drive-a', 'a1', size: 100);
      await addFile('drive-a', 'a2', size: 250);
      await addFile('drive-b', 'b1', size: 7);

      final summaries = await driveDao.driveContentSummaries();

      expect(summaries['drive-a']!.totalSize, 350);
      expect(summaries['drive-b']!.totalSize, 7);
    });

    test('a drive with no local rows is absent rather than zero-sized',
        () async {
      await addDrive('drive-a');
      await addDrive('drive-unsynced');
      await addFile('drive-a', 'a1', size: 100);

      final summaries = await driveDao.driveContentSummaries();

      // The page reads absence as "nothing here yet", and decides separately
      // whether that means empty or never walked.
      expect(summaries.containsKey('drive-unsynced'), isFalse);
    });

    test('a hidden file is still a file that was synced', () async {
      await addDrive('drive-a');
      await addFile('drive-a', 'a1', size: 100);
      await addFile('drive-a', 'a2', size: 100, isHidden: true);

      final summaries = await driveDao.driveContentSummaries();

      expect(summaries['drive-a']!.itemCount, 2);
      expect(summaries['drive-a']!.totalSize, 200);
    });
  });
}
