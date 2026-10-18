import 'dart:async';

import 'package:ardrive/blocs/hide/global_hide_bloc.dart';
import 'package:ardrive/search/domain/repository/search_repository.dart';
import 'package:ardrive/search/domain/search_coverage.dart';
import 'package:ardrive/search/search_result.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'search_event.dart';
part 'search_state.dart';

/// Search for one signed-in session, shared by every place a search is typed:
/// the search box on each page, its dropdown, and the full results.
///
/// It lives as long as the session (see `SearchScope`) rather than as long as a
/// search box. The box is rebuilt whenever the page under it changes state,
/// and a sync started from it finishes on a page that has a different box.
class SearchBloc extends Bloc<SearchEvent, SearchState> {
  final SearchRepository _searchRepository;
  final SyncCubit _syncCubit;
  final GlobalHideBloc _globalHideBloc;
  final Duration _debounce;

  late final StreamSubscription<SyncState> _syncSubscription;
  late final StreamSubscription<GlobalHideState> _hideSubscription;
  late final StreamSubscription<void> _drivesSubscription;

  /// The newest query received, which a search after a sync runs again. Not
  /// the one last shown: that can be a query the reader has typed past.
  String _latestQuery = '';

  SyncState _lastSyncState;

  /// How the last sync asked for here ended, while it still applies. See
  /// [SearchSyncStatus.failed] and [SearchSyncStatus.refused].
  SearchSyncStatus? _syncOutcome;
  int _failedSyncCount = 0;

  SearchBloc(
    this._searchRepository, {
    required SyncCubit syncCubit,
    required GlobalHideBloc globalHideBloc,
    Duration debounce = const Duration(milliseconds: 250),
  })  : _syncCubit = syncCubit,
        _globalHideBloc = globalHideBloc,
        _debounce = debounce,
        _lastSyncState = syncCubit.state,
        super(const SearchState()) {
    // One handler for everything that searches, restarted by each new event,
    // so only the newest query's results are ever shown. Separate handlers
    // would not cancel one another: a search still running for "abc" landed
    // after the field had been cleared.
    on<_SearchQueryEvent>(_onQuery, transformer: restartable());
    on<_SearchCoverageChanged>(_onCoverageChanged, transformer: restartable());
    on<SearchSyncRequested>(_onSyncRequested, transformer: droppable());

    _syncSubscription = _syncCubit.stream.listen((syncState) {
      final previous = _lastSyncState;
      _lastSyncState = syncState;

      if (previous.runtimeType != syncState.runtimeType) {
        add(const _SearchCoverageChanged());
      }

      if (previous is SyncInProgress && syncState is! SyncInProgress) {
        add(const _SearchRerun());
      }
    });

    _hideSubscription = _globalHideBloc.stream
        .distinct((a, b) => _showsHidden(a) == _showsHidden(b))
        .listen((_) => add(const _SearchCoverageChanged()));

    _drivesSubscription = _searchRepository
        .watchDrives()
        .listen((_) => add(const _SearchCoverageChanged()));
  }

  Future<void> _onQuery(
    _SearchQueryEvent event,
    Emitter<SearchState> emit,
  ) async {
    final query = switch (event) {
      SearchQueryChanged(:final query) => query,
      SearchSubmitted(:final query) => query,
      _SearchRerun() => _latestQuery,
    };

    if (event is! _SearchRerun) {
      _latestQuery = query;
    }

    if (query.isEmpty) {
      emit(state.copyWith(
        query: '',
        status: SearchStatus.idle,
        results: const [],
      ));
      return;
    }

    if (event is SearchQueryChanged) {
      await Future.delayed(_debounce);

      if (emit.isDone) {
        return;
      }
    }

    // A search after a sync replaces the results in place: saying "loading"
    // over the same query would flash.
    if (event is! _SearchRerun) {
      emit(state.copyWith(query: query, status: SearchStatus.loading));
    }

    final searched = await Future.wait([
      _searchRepository.search(query),
      _coverage(),
    ]);

    if (emit.isDone) {
      return;
    }

    final results = searched[0] as List<SearchResult>;
    final coverage = searched[1] as SearchCoverage;

    emit(state.copyWith(
      query: query,
      status: results.isEmpty ? SearchStatus.empty : SearchStatus.success,
      results: results,
      coverage: coverage,
      syncStatus: _syncStatusFor(coverage),
      failedSyncCount: _failedSyncCount,
    ));
  }

  Future<void> _onCoverageChanged(
    _SearchCoverageChanged event,
    Emitter<SearchState> emit,
  ) async {
    final coverage = await _coverage();

    if (emit.isDone) {
      return;
    }

    emit(state.copyWith(
      coverage: coverage,
      syncStatus: _syncStatusFor(coverage),
      failedSyncCount: _failedSyncCount,
    ));
  }

  Future<void> _onSyncRequested(
    SearchSyncRequested event,
    Emitter<SearchState> emit,
  ) async {
    final requested = state.coverage.unsearchedDriveIds;

    if (requested.isEmpty) {
      return;
    }

    _syncOutcome = null;
    _failedSyncCount = 0;
    emit(state.copyWith(syncStatus: SearchSyncStatus.syncing));

    final ran = await _syncCubit.syncDrives(requested);
    final coverage = await _coverage();
    final stillUnsearched =
        requested.where(coverage.unsearchedDriveIds.contains).length;
    final syncState = _syncCubit.state;

    if (syncState is SyncCancelled) {
      // The reader stopped it, so there is nothing to explain: the offer to
      // sync stands.
      _syncOutcome = null;
    } else if (!ran && syncState is! SyncFailure) {
      // False without a failure is a refusal: the sync never started.
      _syncOutcome = SearchSyncStatus.refused;
    } else if (stillUnsearched > 0) {
      // Whether the sync threw or some drives failed in it, these are still
      // not searchable, and offering the same button with nothing said would
      // look like it had done nothing. A private drive this device has no key
      // for fails every time.
      _syncOutcome = SearchSyncStatus.failed;
      _failedSyncCount = stillUnsearched;
    } else {
      _syncOutcome = null;
    }

    emit(state.copyWith(
      coverage: coverage,
      syncStatus: _syncStatusFor(coverage),
      failedSyncCount: _failedSyncCount,
    ));
  }

  Future<SearchCoverage> _coverage() {
    final syncState = _syncCubit.state;

    return _searchRepository.coverage(
      includeHiddenDrives: _showsHidden(_globalHideBloc.state),
      failedDriveIds: syncState is SyncCompleteWithErrors
          ? syncState.failedDriveIds.toSet()
          : const {},
    );
  }

  SearchSyncStatus _syncStatusFor(SearchCoverage coverage) {
    if (coverage.isComplete) {
      _syncOutcome = null;
      _failedSyncCount = 0;
      return SearchSyncStatus.none;
    }

    if (_syncCubit.state is SyncInProgress) {
      final unsearched = coverage.unsearchedDriveIds;
      final singleDrive = _syncCubit.syncingDriveId;
      final runDrives = _syncCubit.syncingDriveIds;

      // A run over every drive (no run set) includes the ones never synced.
      final covers = singleDrive != null
          ? unsearched.contains(singleDrive)
          : runDrives == null || unsearched.any(runDrives.contains);

      return covers
          ? SearchSyncStatus.syncing
          : SearchSyncStatus.otherSyncRunning;
    }

    return _syncOutcome ?? SearchSyncStatus.none;
  }

  static bool _showsHidden(GlobalHideState state) =>
      state is ShowingHiddenItems;

  @override
  Future<void> close() async {
    await _syncSubscription.cancel();
    await _hideSubscription.cancel();
    await _drivesSubscription.cancel();
    return super.close();
  }
}
