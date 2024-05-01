import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/search/domain/bloc/search_bloc.dart';
import 'package:ardrive/search/domain/repository/search_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockSearchRepository extends Mock implements SearchRepository {}

void main() {
  late SearchBloc searchBloc;
  late MockSearchRepository mockSearchRepository;

  setUp(() {
    mockSearchRepository = MockSearchRepository();
    searchBloc = SearchBloc(mockSearchRepository);
  });

  tearDown(() {
    searchBloc.close();
  });

  test('initial state is SearchInitial', () {
    expect(searchBloc.state, equals(SearchInitial()));
  });

  blocTest<SearchBloc, SearchState>(
    'emits [SearchQueryEmpty] when empty query is added',
    build: () => searchBloc,
    act: (bloc) => bloc.add(const SearchQueryChanged('')),
    expect: () => [SearchQueryEmpty()],
  );

  blocTest<SearchBloc, SearchState>(
    'emits [SearchEmpty] when repository returns an empty list',
    build: () => searchBloc,
    setUp: () {
      when(() => mockSearchRepository.search(any()))
          .thenAnswer((_) async => []);
    },
    act: (bloc) => bloc.add(const SearchQueryChanged('query')),
    expect: () => [SearchEmpty()],
  );

  final mockDrive = Drive(
    dateCreated: DateTime.now(),
    id: '',
    rootFolderId: '',
    ownerAddress: '',
    name: '',
    privacy: '',
    lastUpdated: DateTime.now(),
  );

  final SearchResult<String> result1 = SearchResult<String>(
    result: 'result1',
    drive: mockDrive,
  );

  final SearchResult<String> result2 = SearchResult<String>(
    result: 'result2',
    drive: mockDrive,
  );

  blocTest<SearchBloc, SearchState>(
    'emits [SearchSuccess] when repository returns a non-empty list',
    build: () => searchBloc,
    setUp: () {
      when(() => mockSearchRepository.search(any()))
          .thenAnswer((_) async => [result1]);
      when(() => mockSearchRepository.search(any()))
          .thenAnswer((_) async => [result1, result2]);
    },
    act: (bloc) => bloc.add(const SearchQueryChanged('query')),
    expect: () => [
      SearchSuccess([result1, result2]),
    ],
  );
}
