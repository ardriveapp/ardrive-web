part of 'search_bloc.dart';

enum SearchStatus {
  /// Nothing typed.
  idle,

  /// Waiting for results. [SearchState.results] still holds the previous
  /// query's, so a list on screen is replaced rather than blanked.
  loading,

  /// [SearchState.results] are the results for [SearchState.query], and there
  /// is at least one.
  success,

  /// [SearchState.query] matched nothing.
  empty,
}

/// Where syncing the drives search could not look inside stands.
enum SearchSyncStatus {
  /// Nothing to report: the reader can sync them.
  none,

  /// A sync covering some of them is running.
  syncing,

  /// A sync is running that covers none of them. Only one sync runs at a
  /// time, so these cannot be synced until it ends.
  otherSyncRunning,

  /// The sync asked for here ended with some of them still unreadable.
  failed,

  /// The sync asked for here did not start, because something that cannot be
  /// interrupted (an upload) was running.
  refused,
}

class SearchState extends Equatable {
  const SearchState({
    this.query = '',
    this.status = SearchStatus.idle,
    this.results = const [],
    this.coverage = SearchCoverage.unknown,
    this.syncStatus = SearchSyncStatus.none,
    this.failedSyncCount = 0,
  });

  final String query;
  final SearchStatus status;
  final List<SearchResult> results;
  final SearchCoverage coverage;
  final SearchSyncStatus syncStatus;

  /// For [SearchSyncStatus.failed]: how many of the drives asked for are still
  /// unreadable.
  final int failedSyncCount;

  SearchState copyWith({
    String? query,
    SearchStatus? status,
    List<SearchResult>? results,
    SearchCoverage? coverage,
    SearchSyncStatus? syncStatus,
    int? failedSyncCount,
  }) {
    return SearchState(
      query: query ?? this.query,
      status: status ?? this.status,
      results: results ?? this.results,
      coverage: coverage ?? this.coverage,
      syncStatus: syncStatus ?? this.syncStatus,
      failedSyncCount: failedSyncCount ?? this.failedSyncCount,
    );
  }

  @override
  List<Object> get props =>
      [query, status, results, coverage, syncStatus, failedSyncCount];
}
