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
  });

  test('returns empty list if query is empty', () async {
    var results = await searchRepository.search('');
    expect(results, isEmpty);
  });

  test('converts query to lowercase before search', () async {
    when(() => mockDriveDao.search(
          query: any(named: 'query'),
          type: any(named: 'type'),
        )).thenAnswer((_) async => []);

    await searchRepository.search('TestQuery');

    verify(() => mockDriveDao.search(
          query: 'testquery',
          type: SearchQueryType.all,
        )).called(1);
  });

  test('handles spaces and numbers in query', () async {
    when(() => mockDriveDao.search(
          query: any(named: 'query'),
          type: any(named: 'type'),
        )).thenAnswer((_) async => []);

    await searchRepository.search('TestQuery WithSpace and numbers 123');

    verify(() => mockDriveDao.search(
          query: 'testquery withspace and numbers 123',
          type: SearchQueryType.all,
        )).called(1);
  });

  group('duplicate handling', () {
    late Drive testDrive;
    late FileEntry testFile1;
    late FileEntry testFile2;

    setUp(() {
      final now = DateTime.now();

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

      testFile1 = FileEntry(
        id: 'file-1',
        driveId: 'drive-1',
        name: 'test1.txt',
        size: 100,
        lastModifiedDate: now,
        dataContentType: 'text/plain',
        parentFolderId: 'folder-1',
        path: '/test1.txt',
        dataTxId: 'tx-1',
        isHidden: false,
        dateCreated: now,
        lastUpdated: now,
      );

      testFile2 = FileEntry(
        id: 'file-1', // Same ID as testFile1
        driveId: 'drive-1',
        name: 'test1.txt',
        size: 100,
        lastModifiedDate: now,
        dataContentType: 'text/plain',
        parentFolderId: 'folder-1',
        path: '/test1.txt',
        dataTxId: 'tx-1',
        isHidden: false,
        dateCreated: now,
        lastUpdated: now,
      );
    });

    test('identifies and marks duplicate results', () async {
      final result1 = SearchResult(result: testFile1, drive: testDrive);
      final result2 = SearchResult(result: testFile2, drive: testDrive);

      when(() => mockDriveDao.search(
            query: any(named: 'query'),
            type: any(named: 'type'),
          )).thenAnswer((_) async => [result1, result2]);

      final results = await searchRepository.search('test');

      expect(results.length, 2);
      expect(results.where((r) => !r.isDuplicate).length, 1);
      expect(results.where((r) => r.isDuplicate).length, 1);

      final duplicate = results.firstWhere((r) => r.isDuplicate);
      expect(duplicate.originalResult, isNotNull);
      expect(duplicate.uniqueId, equals(results.first.uniqueId));
    });

    test('preserves unique results order', () async {
      final now = DateTime.now();
      final uniqueFile = FileEntry(
        id: 'file-2',
        driveId: 'drive-1',
        name: 'unique.txt',
        size: 100,
        lastModifiedDate: now,
        dataContentType: 'text/plain',
        parentFolderId: 'folder-1',
        path: '/unique.txt',
        dataTxId: 'tx-2',
        isHidden: false,
        dateCreated: now,
        lastUpdated: now,
      );

      final result1 = SearchResult(result: testFile1, drive: testDrive);
      final result2 = SearchResult(result: uniqueFile, drive: testDrive);
      final result3 = SearchResult(result: testFile2, drive: testDrive);

      when(() => mockDriveDao.search(
            query: any(named: 'query'),
            type: any(named: 'type'),
          )).thenAnswer((_) async => [result1, result2, result3]);

      final results = await searchRepository.search('test');

      expect(results.length, 3);
      expect(results[0].isDuplicate, isFalse);
      expect(results[1].isDuplicate, isFalse);
      expect(results[2].isDuplicate, isTrue);
    });
  });
}
