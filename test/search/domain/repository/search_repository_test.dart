import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/search/domain/repository/search_repository.dart';
import 'package:ardrive/search/search_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDriveDao extends Mock implements DriveDao {}

void main() {
  late ArDriveSearchRepository searchRepository;
  late MockDriveDao mockDriveDao;

  setUpAll(() {
    registerFallbackValue(SearchQueryType.name);
    mockDriveDao = MockDriveDao();
    searchRepository = ArDriveSearchRepository(mockDriveDao);
  });

  test('returns empty list if query is empty', () async {
    var results = await searchRepository.search('');
    expect(results, isEmpty);
  });
  test('converts query to lowercase before search', () async {
    when(() => mockDriveDao.search(
        query: any(named: 'query'),
        type: any(named: 'type'))).thenAnswer((_) async => []);

    await searchRepository.search('TestQuery');
    verify(() =>
            mockDriveDao.search(query: 'testquery', type: SearchQueryType.name))
        .called(1);
  });
  test('converts query to lowercase before search', () async {
    when(() => mockDriveDao.search(
        query: any(named: 'query'),
        type: any(named: 'type'))).thenAnswer((_) async => []);

    await searchRepository.search('TestQuery WithSpace and numbers 123');
    verify(() => mockDriveDao.search(
        query: 'testquery withspace and numbers 123',
        type: SearchQueryType.name)).called(1);
  });
}
