import 'dart:async';

import 'package:ardrive/blocs/hide/global_hide_bloc.dart';
import 'package:ardrive/search/domain/repository/search_repository.dart';
import 'package:ardrive/search/domain/search_coverage.dart';
import 'package:ardrive/search/search_result.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rxdart/rxdart.dart';

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

  /// The drives the last sync asked for here covered. Kept as ids rather than
  /// a count, so a later sync that reads some of them makes the count smaller
  /// instead of leaving a number that is no longer true.
  Set<String> _requestedDriveIds = const {};

  int _resultsRevision = 0;

  SearchBloc(
    this._searchRepository, {
    required SyncCubit syncCubit,
    required GlobalHideBloc globalHideBloc,
    Duration debounce = const Duration(milliseconds: 250),
    Duration drivesSettle = const Duration(milliseconds: 500),
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

      if (previous is SyncInProgress && syncState is! SyncInProgress) {
        // Whatever stopped a sync from starting has ended with this one.
        if (_syncOutcome == SearchSyncStatus.refused) {
          _syncOutcome = null;
        }

        add(const _SearchRerun());
      } else if (previous.runtimeType != syncState.runtimeType) {
        add(const _SearchCoverageChanged());
      }
    });

    _hideSubscription = _globalHideBloc.stream
        .distinct((a, b) => _showsHidden(a) == _showsHidden(b))
        .listen((_) => add(const _SearchCoverageChanged()));

    // A sync writes each drive's row as it finishes walking it, so this is
    // also how results catch up with a sync while it runs. With a query, the
    // count and the results move together: counting a drive as searched while
    // listing results from before it was walked said "Searched 3 of 6" over
    // results from two. Settled first, because a sync writes these rows in
    // bursts.
    _drivesSubscription = _searchRepository
        .watchDrives()
        .debounceTime(drivesSettle)
        .listen((_) => add(_latestQuery.isEmpty
            ? const _SearchCoverageChanged()
            : const _SearchRerun()));
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

    final List<Object> searched;

    try {
      searched = await Future.wait([
        _searchRepository.search(query),
        _coverage(),
      ]);
    } catch (error, stackTrace) {
      // Ended rather than left loading: "Searching..." with nothing coming
      // read as a search still running until the reader changed the query.
      addError(error, stackTrace);

      if (!emit.isDone) {
        emit(state.copyWith(
          query: query,
          status: SearchStatus.empty,
          results: const [],
          resultsRevision: ++_resultsRevision,
        ));
      }

      return;
    }

    if (emit.isDone) {
      return;
    }

    final results = searched[0] as List<SearchResult>;
    final coverage = searched[1] as SearchCoverage;

    emit(_withCoverage(
      state.copyWith(
        query: query,
        status: results.isEmpty ? SearchStatus.empty : SearchStatus.success,
        results: results,
        // Results compare by id, so a search after a sync that renamed or
        // moved what it found was equal to the last state and never shown.
        resultsRevision: ++_resultsRevision,
      ),
      coverage,
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

    emit(_withCoverage(state, coverage));
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
    _requestedDriveIds = requested.toSet();
    emit(state.copyWith(
      syncStatus: SearchSyncStatus.syncing,
      syncCount: requested.length,
    ));

    final ran = await _syncCubit.syncDrives(requested);
    final syncState = _syncCubit.state;

    if (syncState is SyncCancelled) {
      // The reader stopped it, so there is nothing to explain: the offer to
      // sync stands.
      _syncOutcome = null;
    } else if (!ran && syncState is SyncInProgress) {
      // Another sync started between the note being drawn and the press. The
      // note already says that while it runs, and offers the button after.
      _syncOutcome = null;
    } else if (!ran && syncState is! SyncFailure) {
      // False without a failure is a refusal: the sync never started.
      _syncOutcome = SearchSyncStatus.refused;
    } else {
      // Whether the sync threw or some drives failed in it, any still not
      // searchable are reported rather than offered again with nothing said,
      // which would look like the button had done nothing. A private drive
      // this device has no key for fails every time. With none left, this
      // reads as nothing to report.
      _syncOutcome = SearchSyncStatus.failed;
    }

    emit(_withCoverage(state, await _coverage()));
  }

  Future<SearchCoverage> _coverage() => _searchRepository.coverage(
        includeHiddenDrives: _showsHidden(_globalHideBloc.state),
      );

  /// [state] with [coverage], and where syncing the drives it could not search
  /// stands now.
  SearchState _withCoverage(SearchState state, SearchCoverage coverage) {
    final unsearched = coverage.unsearchedDriveIds;

    if (unsearched.isEmpty) {
      _syncOutcome = null;
      _requestedDriveIds = const {};

      return state.copyWith(
        coverage: coverage,
        syncStatus: SearchSyncStatus.none,
        syncCount: 0,
      );
    }

    if (_syncCubit.state is SyncInProgress) {
      final singleDrive = _syncCubit.syncingDriveId;
      final runDrives = _syncCubit.syncingDriveIds;

      // How many of them the running sync covers. A run over every drive (no
      // run set) includes the ones never synced; a drive page's sync covers
      // one.
      final covered = singleDrive != null
          ? (unsearched.contains(singleDrive) ? 1 : 0)
          : runDrives == null
              ? unsearched.length
              : unsearched.where(runDrives.contains).length;

      return state.copyWith(
        coverage: coverage,
        syncStatus: covered > 0
            ? SearchSyncStatus.syncing
            : SearchSyncStatus.otherSyncRunning,
        syncCount: covered,
      );
    }

    if (_syncOutcome == SearchSyncStatus.failed) {
      final stillUnsearched =
          unsearched.where(_requestedDriveIds.contains).length;

      if (stillUnsearched == 0) {
        _syncOutcome = null;
      } else {
        return state.copyWith(
          coverage: coverage,
          syncStatus: SearchSyncStatus.failed,
          syncCount: stillUnsearched,
        );
      }
    }

    return state.copyWith(
      coverage: coverage,
      syncStatus: _syncOutcome ?? SearchSyncStatus.none,
      syncCount: 0,
    );
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
