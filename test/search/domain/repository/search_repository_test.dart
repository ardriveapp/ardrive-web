import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/search/search_result.dart';
import 'package:ardrive/search/domain/repository/search_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDriveDao extends Mock implements DriveDao {}

void main() {
  late ArDriveSearchRepository searchRepository;
  late MockDriveDao mockDriveDao;

  setUp(() {
    registerFallbackValue(SearchQueryType.all);
    mockDriveDao = MockDriveDao();

    searchRepository = ArDriveSearchRepository(mockDriveDao);

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
}
