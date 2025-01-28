import 'package:ardrive/arns/data/arns_dao.dart';
import 'package:ardrive/core/arfs/repository/file_repository.dart';
import 'package:ardrive/core/arfs/repository/folder_repository.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/search/domain/repository/search_repository.dart';
import 'package:ardrive/search/search_result.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDriveDao extends Mock implements DriveDao {}

class MockArnsDao extends Mock implements ARNSDao {}

class MockFileRepository extends Mock implements FileRepository {}

class MockFolderRepository extends Mock implements FolderRepository {}

class MockSelectable<T> extends Mock implements drift.Selectable<T> {}

void main() {
  late ArDriveSearchRepository searchRepository;
  late MockDriveDao mockDriveDao;
  late MockArnsDao mockArnsDao;
  late MockFileRepository mockFileRepository;
  late MockFolderRepository mockFolderRepository;

  setUp(() {
    registerFallbackValue(SearchQueryType.all);
    mockDriveDao = MockDriveDao();
    mockArnsDao = MockArnsDao();
    mockFileRepository = MockFileRepository();
    mockFolderRepository = MockFolderRepository();

    searchRepository = ArDriveSearchRepository(
      mockDriveDao,
      mockArnsDao,
      mockFileRepository,
      mockFolderRepository,
    );

    // Setup default responses for ARNS search
    final mockSelectable = MockSelectable<ArnsRecord>();
    when(() => mockArnsDao.getActiveARNSRecordByName(
          domain: any(named: 'domain'),
          name: any(named: 'name'),
        )).thenReturn(mockSelectable);
    when(() => mockSelectable.getSingleOrNull()).thenAnswer((_) async => null);

    // Setup default response for drive search
    when(() => mockDriveDao.search(
          query: any(named: 'query'),
          type: any(named: 'type'),
        )).thenAnswer((_) async => []);
  });

  test('returns empty list if query is empty', () async {
    var results = await searchRepository.search('');
    expect(results, isEmpty);
  });

  test('handles spaces and numbers in query', () async {
    await searchRepository.search('TestQuery WithSpace and numbers 123');

    verify(() => mockDriveDao.search(
          query: 'TestQuery WithSpace and numbers 123',
          type: SearchQueryType.all,
        )).called(1);
  });

  group('ARNS search', () {
    late ArnsRecord testArnsRecord;
    late FileEntry testFile;
    late Drive testDrive;
    late FolderEntry testParentFolder;

    setUp(() {
      final now = DateTime.now();
      testArnsRecord = const ArnsRecord(
        id: 'test-id',
        transactionId: 'tx-1',
        fileId: 'file-1',
        ttl: 3600,
        name: 'test',
        domain: 'test.ar',
        isActive: true,
      );

      testFile = FileEntry(
        id: 'file-1',
        driveId: 'drive-1',
        name: 'test.txt',
        size: 100,
        lastModifiedDate: now,
        dataContentType: 'text/plain',
        parentFolderId: 'folder-1',
        path: '/test.txt',
        dataTxId: 'tx-1',
        isHidden: false,
        dateCreated: now,
        lastUpdated: now,
      );

      testDrive = Drive(
        id: 'drive-1',
        name: 'Test Drive',
        privacy: 'public',
        rootFolderId: 'root-1',
        ownerAddress: 'owner-1',
        isHidden: false,
        dateCreated: now,
        lastUpdated: now,
      );

      testParentFolder = FolderEntry(
        id: 'folder-1',
        driveId: 'drive-1',
        name: 'test-folder',
        parentFolderId: 'root-1',
        path: '/test-folder',
        dateCreated: now,
        lastUpdated: now,
        isHidden: false,
        isGhost: false,
      );
    });

    test('includes ARNS results in search', () async {
      final mockSelectable = MockSelectable<ArnsRecord>();
      when(() => mockArnsDao.getActiveARNSRecordByName(
            domain: '',
            name: 'test',
          )).thenReturn(mockSelectable);
      when(() => mockSelectable.getSingleOrNull())
          .thenAnswer((_) async => testArnsRecord);

      when(() => mockFileRepository.getFileEntryById('file-1'))
          .thenAnswer((_) async => testFile);
      when(() => mockDriveDao.driveById(driveId: 'drive-1'))
          .thenReturn(MockSelectable<Drive>());
      when(() => mockDriveDao.driveById(driveId: 'drive-1').getSingle())
          .thenAnswer((_) async => testDrive);
      when(() => mockFolderRepository.getFolderEntryById('folder-1'))
          .thenAnswer((_) async => testParentFolder);
      when(() => mockDriveDao.search(
            query: 'test',
            type: SearchQueryType.all,
          )).thenAnswer((_) async => [
            SearchResult(
              result: testFile,
              drive: testDrive,
              parentFolder: testParentFolder,
              hasArNSName: true,
            ),
          ]);

      final results = await searchRepository.search('test');

      expect(results, isNotEmpty);
      expect(results.first.result, equals(testFile));
      expect(results.first.drive, equals(testDrive));
      expect(results.first.parentFolder, equals(testParentFolder));
      expect(results.first.hasArNSName, isTrue);
    });
  });
}
