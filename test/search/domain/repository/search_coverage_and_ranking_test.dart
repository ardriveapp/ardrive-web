import 'package:ardrive/arns/data/arns_dao.dart';
import 'package:ardrive/core/arfs/repository/file_repository.dart';
import 'package:ardrive/core/arfs/repository/folder_repository.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/search/domain/repository/search_repository.dart';
import 'package:ardrive/search/search_result.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../test_utils/utils.dart';

class MockFileRepository extends Mock implements FileRepository {}

class MockFolderRepository extends Mock implements FolderRepository {}

/// Against a real database, because the rules under test are in SQL: which
/// drives count as searched, and which matches survive the limit.
void main() {
  late Database db;
  late DriveDao driveDao;
  late ArDriveSearchRepository repository;

  setUp(() {
    db = getTestDb();
    driveDao = db.driveDao;
    repository = ArDriveSearchRepository(
      driveDao,
      ARNSDao(db),
      MockFileRepository(),
      MockFolderRepository(),
    );
  });

  tearDown(() async => db.close());

  Future<void> drive(
    String id, {
    int? lastBlockHeight,
    bool isHidden = false,
    String? name,
  }) =>
      db.into(db.drives).insert(DrivesCompanion.insert(
            id: id,
            rootFolderId: '$id-root',
            ownerAddress: 'owner',
            name: name ?? id,
            privacy: DrivePrivacyTag.public,
            lastBlockHeight: Value(lastBlockHeight),
            isHidden: Value(isHidden),
          ));

  Future<void> rootRevision(String driveId) =>
      db.into(db.folderRevisions).insert(FolderRevisionsCompanion.insert(
            folderId: '$driveId-root',
            driveId: driveId,
            name: driveId,
            metadataTxId: 'tx',
            action: RevisionAction.create,
          ));

  Future<void> folder(
    String id, {
    required String driveId,
    required String name,
    String? parentFolderId,
    bool isHidden = false,
  }) =>
      db.into(db.folderEntries).insert(FolderEntriesCompanion.insert(
            id: id,
            driveId: driveId,
            name: name,
            parentFolderId: Value(parentFolderId),
            path: '',
            isHidden: Value(isHidden),
          ));

  Future<void> file(
    String id, {
    required String driveId,
    required String name,
    required String parentFolderId,
    bool isHidden = false,
  }) =>
      db.into(db.fileEntries).insert(FileEntriesCompanion.insert(
            id: id,
            driveId: driveId,
            parentFolderId: parentFolderId,
            name: name,
            dataTxId: '$id-tx',
            size: 1,
            lastModifiedDate: DateTime(2024),
            path: '',
            isHidden: Value(isHidden),
          ));

  group('coverage', () {
    setUp(() async {
      // Walked by a sync.
      await drive('synced', lastBlockHeight: 1500000);
      // Made on this device, so its root revision is here, and nothing else.
      await drive('created-here');
      await rootRevision('created-here');
      // Only discovered at login.
      await drive('discovered');
      await drive('hidden-discovered', isHidden: true);
    });

    test(
        'counts a drive as searched when a sync walked it or its root '
        'folder is here, as the drive page does', () async {
      final coverage = await repository.coverage(includeHiddenDrives: false);

      expect(coverage.totalDrives, 3);
      expect(coverage.unsearchedDriveIds, ['discovered']);
      expect(coverage.searchedDrives, 2);
    });

    test('leaves hidden drives out unless hidden items are shown', () async {
      final coverage = await repository.coverage(includeHiddenDrives: true);

      expect(coverage.totalDrives, 4);
      expect(
        coverage.unsearchedDriveIds,
        unorderedEquals(['discovered', 'hidden-discovered']),
      );
    });

    test('counts a drive whose last sync failed as not searched', () async {
      final coverage = await repository.coverage(
        includeHiddenDrives: false,
        failedDriveIds: {'synced'},
      );

      expect(
        coverage.unsearchedDriveIds,
        unorderedEquals(['synced', 'discovered']),
      );
    });

    test('is complete with no drives at all', () async {
      await db.delete(db.drives).go();

      final coverage = await repository.coverage(includeHiddenDrives: true);

      expect(coverage.totalDrives, 0);
      expect(coverage.isComplete, isTrue);
    });
  });

  group('results', () {
    setUp(() async {
      await drive('photos', name: 'Photos', isHidden: true);
      await folder('photos-root', driveId: 'photos', name: 'Photos');
      await folder(
        'trips',
        driveId: 'photos',
        name: 'Trips',
        parentFolderId: 'photos-root',
        isHidden: true,
      );
    });

    test('names the folder an item is in, but not the top of its drive',
        () async {
      await file(
        'at-top',
        driveId: 'photos',
        name: 'beach.jpg',
        parentFolderId: 'photos-root',
      );
      await file(
        'in-folder',
        driveId: 'photos',
        name: 'beach-2.jpg',
        parentFolderId: 'trips',
      );

      final results = await repository.search('beach');
      final byId = {for (final r in results) (r.result as FileEntry).id: r};

      expect(byId['at-top']!.parentFolder, isNull);
      expect(byId['in-folder']!.parentFolder!.name, 'Trips');
      expect(byId['at-top']!.drive.name, 'Photos');
    });

    test('carries whether an item and its drive are hidden', () async {
      await file(
        'hidden',
        driveId: 'photos',
        name: 'secret.txt',
        parentFolderId: 'trips',
        isHidden: true,
      );

      final results = await repository.search('');
      expect(results, isEmpty);

      final fileResult = (await repository.search('secret')).single;
      final folderResult = (await repository.search('trips')).single;

      expect((fileResult.result as FileEntry).isHidden, isTrue);
      expect(fileResult.drive.isHidden, isTrue);
      expect((folderResult.result as FolderEntry).isHidden, isTrue);
    });

    test('a file whose folder is not on this device is still found', () async {
      await file(
        'orphan',
        driveId: 'photos',
        name: 'orphan.txt',
        parentFolderId: 'not-synced-yet',
      );

      final result = (await repository.search('orphan')).single;

      expect(result.parentFolder, isNull);
    });

    test('the best match survives the limit when many names contain the query',
        () async {
      // Sixty names that contain "report" and sort before "report.pdf".
      for (var i = 0; i < 60; i++) {
        await file(
          'annual-$i',
          driveId: 'photos',
          name: 'annual report ${i.toString().padLeft(2, '0')}',
          parentFolderId: 'trips',
        );
      }
      await file(
        'exact',
        driveId: 'photos',
        name: 'Report',
        parentFolderId: 'trips',
      );
      await file(
        'prefix',
        driveId: 'photos',
        name: 'report.pdf',
        parentFolderId: 'trips',
      );

      final results = await repository.search('report');
      final ids = [for (final r in results) (r.result as FileEntry).id];

      expect(ids.take(2), ['exact', 'prefix']);
    });
  });

  group('rankSearchResults', () {
    final drive = Drive(
      id: 'd',
      rootFolderId: 'r',
      ownerAddress: '',
      name: 'd',
      privacy: 'public',
      dateCreated: DateTime(2024),
      lastUpdated: DateTime(2024),
      isHidden: false,
    );

    SearchResult fileNamed(String name, {bool arns = false}) => SearchResult(
          result: FileEntry(
            id: name,
            driveId: 'd',
            name: name,
            parentFolderId: 'r',
            path: '',
            size: 1,
            lastModifiedDate: DateTime(2024),
            dataTxId: 'tx',
            dateCreated: DateTime(2024),
            lastUpdated: DateTime(2024),
            isHidden: false,
          ),
          drive: drive,
          hasArNSName: arns,
        );

    SearchResult folderNamed(String name) => SearchResult(
          result: FolderEntry(
            id: name,
            driveId: 'd',
            name: name,
            path: '',
            dateCreated: DateTime(2024),
            lastUpdated: DateTime(2024),
            isGhost: false,
            isHidden: false,
          ),
          drive: drive,
        );

    List<String> names(List<SearchResult> results) =>
        results.map(searchResultName).toList();

    test('orders the whole name, its start, a word start, then anywhere', () {
      final ranked = rankSearchResults('report', [
        fileNamed('quarterlyreport.txt'),
        fileNamed('2024 report.pdf'),
        fileNamed('Report-final.pdf'),
        fileNamed('REPORT'),
        fileNamed('annual_report.doc'),
      ]);

      expect(names(ranked), [
        'REPORT',
        'Report-final.pdf',
        '2024 report.pdf',
        'annual_report.doc',
        'quarterlyreport.txt',
      ]);
    });

    test('puts an ArNS match first, as it was before ranking', () {
      final ranked = rankSearchResults('photos', [
        fileNamed('photos'),
        fileNamed('cat.jpg', arns: true),
      ]);

      expect(names(ranked), ['cat.jpg', 'photos']);
    });

    test('breaks a tie with folders before files, then in name order', () {
      final ranked = rankSearchResults('trip', [
        fileNamed('trip 10'),
        fileNamed('trip 9'),
        folderNamed('trip 2'),
      ]);

      expect(names(ranked), ['trip 2', 'trip 9', 'trip 10']);
    });

    test('lists a name matched only by a LIKE wildcard last', () {
      final ranked = rankSearchResults('a_b', [
        fileNamed('axb'),
        fileNamed('a_b'),
      ]);

      expect(names(ranked), ['a_b', 'axb']);
    });
  });
}
