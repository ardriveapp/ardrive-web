import 'dart:async';

import 'package:ardrive/blocs/hide/global_hide_bloc.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/search/domain/bloc/search_bloc.dart';
import 'package:ardrive/search/domain/repository/search_repository.dart';
import 'package:ardrive/search/domain/search_coverage.dart';
import 'package:ardrive/search/search_result.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockSearchRepository extends Mock implements SearchRepository {}

class MockSyncCubit extends MockCubit<SyncState> implements SyncCubit {}

class MockGlobalHideBloc extends MockBloc<GlobalHideEvent, GlobalHideState>
    implements GlobalHideBloc {}

void main() {
  late MockSearchRepository repository;
  late MockSyncCubit syncCubit;
  late MockGlobalHideBloc globalHideBloc;
  late StreamController<SyncState> syncStates;
  late StreamController<GlobalHideState> hideStates;
  late StreamController<void> drivesChanges;

  const debounce = Duration(milliseconds: 250);

  final drive = Drive(
    dateCreated: DateTime(2024),
    id: 'drive',
    rootFolderId: 'root',
    ownerAddress: '',
    name: 'Drive',
    privacy: 'public',
    lastUpdated: DateTime(2024),
    isHidden: false,
  );

  SearchResult<String> result(String id) =>
      SearchResult<String>(result: id, drive: drive, uniqueId: id);

  const complete = SearchCoverage(totalDrives: 3);
  const partial =
      SearchCoverage(totalDrives: 3, unsearchedDriveIds: ['b', 'c']);

  SearchBloc build({Duration wait = debounce}) => SearchBloc(
        repository,
        syncCubit: syncCubit,
        globalHideBloc: globalHideBloc,
        debounce: wait,
      );

  setUp(() {
    repository = MockSearchRepository();
    syncCubit = MockSyncCubit();
    globalHideBloc = MockGlobalHideBloc();
    syncStates = StreamController<SyncState>.broadcast();
    hideStates = StreamController<GlobalHideState>.broadcast();
    drivesChanges = StreamController<void>.broadcast();

    when(() => syncCubit.state).thenReturn(SyncIdle());
    when(() => syncCubit.stream).thenAnswer((_) => syncStates.stream);
    when(() => syncCubit.syncingDriveId).thenReturn(null);
    when(() => syncCubit.syncingDriveIds).thenReturn(null);
    when(() => globalHideBloc.state)
        .thenReturn(const HiddingItems(userHasHiddenDrive: false));
    when(() => globalHideBloc.stream).thenAnswer((_) => hideStates.stream);
    when(() => repository.watchDrives())
        .thenAnswer((_) => drivesChanges.stream);
    when(() => repository.search(any())).thenAnswer((_) async => []);
    when(() => repository.coverage(
          includeHiddenDrives: any(named: 'includeHiddenDrives'),
          failedDriveIds: any(named: 'failedDriveIds'),
        )).thenAnswer((_) async => complete);
  });

  tearDown(() async {
    await syncStates.close();
    await hideStates.close();
    await drivesChanges.close();
  });

  test('starts with nothing searched and nothing claimed', () {
    final bloc = build();

    expect(bloc.state, const SearchState());
    expect(bloc.state.coverage.isComplete, isTrue);

    bloc.close();
  });

  group('searching', () {
    blocTest<SearchBloc, SearchState>(
      'an empty query is idle at once, without the pause',
      build: () => build(wait: const Duration(hours: 1)),
      act: (bloc) => bloc.add(const SearchQueryChanged('')),
      expect: () => [const SearchState()],
    );

    blocTest<SearchBloc, SearchState>(
      'waits for the pause, then loads and lists the results',
      setUp: () {
        when(() => repository.search('report'))
            .thenAnswer((_) async => [result('a'), result('b')]);
      },
      build: build,
      act: (bloc) => bloc.add(const SearchQueryChanged('report')),
      wait: debounce * 2,
      expect: () => [
        const SearchState(query: 'report', status: SearchStatus.loading),
        SearchState(
          query: 'report',
          status: SearchStatus.success,
          results: [result('a'), result('b')],
          coverage: complete,
        ),
      ],
    );

    blocTest<SearchBloc, SearchState>(
      'a query that matches nothing is empty',
      build: build,
      act: (bloc) => bloc.add(const SearchQueryChanged('zzz')),
      wait: debounce * 2,
      expect: () => [
        const SearchState(query: 'zzz', status: SearchStatus.loading),
        const SearchState(
          query: 'zzz',
          status: SearchStatus.empty,
          coverage: complete,
        ),
      ],
    );

    blocTest<SearchBloc, SearchState>(
      'a word typed quickly is one search, for the whole word',
      build: build,
      act: (bloc) async {
        bloc.add(const SearchQueryChanged('r'));
        await Future.delayed(const Duration(milliseconds: 50));
        bloc.add(const SearchQueryChanged('re'));
        await Future.delayed(const Duration(milliseconds: 50));
        bloc.add(const SearchQueryChanged('rep'));
      },
      wait: debounce * 2,
      verify: (_) {
        verify(() => repository.search('rep')).called(1);
        verifyNever(() => repository.search('r'));
        verifyNever(() => repository.search('re'));
      },
    );

    blocTest<SearchBloc, SearchState>(
      'a slow search for an older query never replaces a newer one',
      setUp: () {
        final slow = Completer<List<SearchResult>>();

        when(() => repository.search('rep')).thenAnswer((_) => slow.future);
        when(() => repository.search('report'))
            .thenAnswer((_) async => [result('new')]);

        // Answers only after "report" has been shown.
        Future.delayed(debounce * 3, () => slow.complete([result('old')]));
      },
      build: build,
      act: (bloc) async {
        bloc.add(const SearchSubmitted('rep'));
        await Future.delayed(const Duration(milliseconds: 20));
        bloc.add(const SearchSubmitted('report'));
      },
      wait: debounce * 4,
      verify: (bloc) {
        expect(bloc.state.query, 'report');
        expect(bloc.state.results, [result('new')]);
      },
    );

    blocTest<SearchBloc, SearchState>(
      'clearing the field cancels a search still waiting or running',
      setUp: () {
        when(() => repository.search('abc'))
            .thenAnswer((_) async => [result('a')]);
      },
      build: build,
      act: (bloc) async {
        bloc.add(const SearchQueryChanged('abc'));
        await Future.delayed(const Duration(milliseconds: 50));
        bloc.add(const SearchQueryChanged(''));
      },
      wait: debounce * 2,
      expect: () => [const SearchState()],
      verify: (_) => verifyNever(() => repository.search('abc')),
    );

    blocTest<SearchBloc, SearchState>(
      'Enter searches without the pause',
      setUp: () {
        when(() => repository.search('report'))
            .thenAnswer((_) async => [result('a')]);
      },
      build: () => build(wait: const Duration(hours: 1)),
      act: (bloc) => bloc.add(const SearchSubmitted('report')),
      expect: () => [
        const SearchState(query: 'report', status: SearchStatus.loading),
        SearchState(
          query: 'report',
          status: SearchStatus.success,
          results: [result('a')],
          coverage: complete,
        ),
      ],
    );
  });

  group('what was searched', () {
    blocTest<SearchBloc, SearchState>(
      'carries the drives that could not be searched with the results',
      setUp: () {
        when(() => repository.coverage(
              includeHiddenDrives: any(named: 'includeHiddenDrives'),
              failedDriveIds: any(named: 'failedDriveIds'),
            )).thenAnswer((_) async => partial);
      },
      build: build,
      act: (bloc) => bloc.add(const SearchSubmitted('report')),
      skip: 1,
      expect: () => [
        const SearchState(
          query: 'report',
          status: SearchStatus.empty,
          coverage: partial,
        ),
      ],
    );

    blocTest<SearchBloc, SearchState>(
      'counts hidden drives only while hidden items are shown',
      setUp: () {
        when(() => globalHideBloc.state)
            .thenReturn(const ShowingHiddenItems(userHasHiddenDrive: true));
      },
      build: build,
      act: (bloc) => bloc.add(const SearchSubmitted('report')),
      verify: (_) {
        verify(() => repository.coverage(
              includeHiddenDrives: true,
              failedDriveIds: const {},
            )).called(1);
      },
    );

    blocTest<SearchBloc, SearchState>(
      'counts a drive whose last sync failed as not searched',
      setUp: () {
        when(() => syncCubit.state).thenReturn(SyncCompleteWithErrors(
          failedDrives: 1,
          totalDrives: 3,
          failedDriveIds: const ['b'],
          errorMessages: const {},
        ));
      },
      build: build,
      act: (bloc) => bloc.add(const SearchSubmitted('report')),
      verify: (_) {
        verify(() => repository.coverage(
              includeHiddenDrives: false,
              failedDriveIds: {'b'},
            )).called(1);
      },
    );

    blocTest<SearchBloc, SearchState>(
      'recounts when the drives change, the hide toggle flips, or a sync '
      'starts',
      build: build,
      act: (bloc) async {
        drivesChanges.add(null);
        await Future.delayed(Duration.zero);
        hideStates.add(const ShowingHiddenItems(userHasHiddenDrive: false));
        await Future.delayed(Duration.zero);
        syncStates.add(SyncInProgress());
        await Future.delayed(Duration.zero);
      },
      verify: (_) {
        verify(() => repository.coverage(
              includeHiddenDrives: any(named: 'includeHiddenDrives'),
              failedDriveIds: any(named: 'failedDriveIds'),
            )).called(3);
      },
    );
  });

  group('syncing what was not searched', () {
    setUp(() {
      when(() => repository.coverage(
            includeHiddenDrives: any(named: 'includeHiddenDrives'),
            failedDriveIds: any(named: 'failedDriveIds'),
          )).thenAnswer((_) async => partial);
    });

    Future<void> searchFirst(SearchBloc bloc) async {
      bloc.add(const SearchSubmitted('report'));
      await Future.delayed(const Duration(milliseconds: 20));
    }

    blocTest<SearchBloc, SearchState>(
      'syncs exactly the drives that were not searched, then searches again',
      setUp: () {
        when(() => syncCubit.syncDrives(any())).thenAnswer((_) async {
          syncStates.add(SyncInProgress());
          await Future.delayed(Duration.zero);
          when(() => repository.coverage(
                includeHiddenDrives: any(named: 'includeHiddenDrives'),
                failedDriveIds: any(named: 'failedDriveIds'),
              )).thenAnswer((_) async => complete);
          when(() => repository.search('report'))
              .thenAnswer((_) async => [result('found-after-sync')]);
          syncStates.add(SyncIdle());
          return true;
        });
      },
      build: build,
      act: (bloc) async {
        await searchFirst(bloc);
        bloc.add(const SearchSyncRequested());
      },
      wait: const Duration(milliseconds: 100),
      verify: (bloc) {
        verify(() => syncCubit.syncDrives(['b', 'c'])).called(1);
        expect(bloc.state.results, [result('found-after-sync')]);
        expect(bloc.state.coverage, complete);
        expect(bloc.state.syncStatus, SearchSyncStatus.none);
      },
    );

    blocTest<SearchBloc, SearchState>(
      'says the sync is running while it covers them',
      setUp: () {
        when(() => syncCubit.state).thenReturn(SyncInProgress());
        when(() => syncCubit.syncingDriveIds).thenReturn({'b', 'c'});
      },
      build: build,
      act: searchFirst,
      verify: (bloc) => expect(bloc.state.syncStatus, SearchSyncStatus.syncing),
    );

    blocTest<SearchBloc, SearchState>(
      'says another sync is running when the one running covers none of them',
      setUp: () {
        when(() => syncCubit.state).thenReturn(SyncInProgress());
        when(() => syncCubit.syncingDriveId).thenReturn('a');
      },
      build: build,
      act: searchFirst,
      verify: (bloc) =>
          expect(bloc.state.syncStatus, SearchSyncStatus.otherSyncRunning),
    );

    blocTest<SearchBloc, SearchState>(
      'a sync over every drive covers them',
      setUp: () => when(() => syncCubit.state).thenReturn(SyncInProgress()),
      build: build,
      act: searchFirst,
      verify: (bloc) => expect(bloc.state.syncStatus, SearchSyncStatus.syncing),
    );

    blocTest<SearchBloc, SearchState>(
      'says so when the sync was refused',
      setUp: () {
        when(() => syncCubit.syncDrives(any())).thenAnswer((_) async => false);
      },
      build: build,
      act: (bloc) async {
        await searchFirst(bloc);
        bloc.add(const SearchSyncRequested());
      },
      wait: const Duration(milliseconds: 50),
      verify: (bloc) => expect(bloc.state.syncStatus, SearchSyncStatus.refused),
    );

    blocTest<SearchBloc, SearchState>(
      'says how many are still unreadable when the sync failed for some',
      setUp: () {
        when(() => syncCubit.syncDrives(any())).thenAnswer((_) async {
          when(() => syncCubit.state).thenReturn(SyncCompleteWithErrors(
            failedDrives: 1,
            totalDrives: 3,
            failedDriveIds: const ['c'],
            errorMessages: const {},
          ));
          when(() => repository.coverage(
                    includeHiddenDrives: any(named: 'includeHiddenDrives'),
                    failedDriveIds: any(named: 'failedDriveIds'),
                  ))
              .thenAnswer((_) async => const SearchCoverage(
                  totalDrives: 3, unsearchedDriveIds: ['c']));
          return true;
        });
      },
      build: build,
      act: (bloc) async {
        await searchFirst(bloc);
        bloc.add(const SearchSyncRequested());
      },
      wait: const Duration(milliseconds: 50),
      verify: (bloc) {
        expect(bloc.state.syncStatus, SearchSyncStatus.failed);
        expect(bloc.state.failedSyncCount, 1);
      },
    );

    blocTest<SearchBloc, SearchState>(
      'offers the sync again when the reader cancelled it',
      setUp: () {
        when(() => syncCubit.syncDrives(any())).thenAnswer((_) async {
          when(() => syncCubit.state).thenReturn(SyncCancelled(
            drivesCompleted: 0,
            totalDrives: 2,
            cancelledAt: DateTime(2024),
          ));
          return true;
        });
      },
      build: build,
      act: (bloc) async {
        await searchFirst(bloc);
        bloc.add(const SearchSyncRequested());
      },
      wait: const Duration(milliseconds: 50),
      verify: (bloc) => expect(bloc.state.syncStatus, SearchSyncStatus.none),
    );

    blocTest<SearchBloc, SearchState>(
      'searches the newest query again when any sync ends, without loading',
      setUp: () {
        var calls = 0;
        when(() => repository.search('report')).thenAnswer(
          (_) async => [result('call-${++calls}')],
        );
      },
      build: build,
      act: (bloc) async {
        await searchFirst(bloc);
        syncStates.add(SyncInProgress());
        await Future.delayed(Duration.zero);
        syncStates.add(SyncIdle());
      },
      wait: const Duration(milliseconds: 50),
      verify: (bloc) {
        expect(bloc.state.results, [result('call-2')]);
        expect(bloc.state.status, SearchStatus.success);
      },
    );
  });
}
