part of 'search_bloc.dart';

sealed class SearchEvent extends Equatable {
  const SearchEvent();

  @override
  List<Object> get props => [];
}

/// The events that run a search. One handler takes them all, so a newer one
/// cancels an older one whichever kind each is.
sealed class _SearchQueryEvent extends SearchEvent {
  const _SearchQueryEvent();
}

/// The text in the search field changed. Searched after a short pause, so a
/// word typed quickly is one search, not one per letter.
class SearchQueryChanged extends _SearchQueryEvent {
  final String query;

  const SearchQueryChanged(this.query);

  @override
  List<Object> get props => [query];
}

/// The reader asked for results now, by pressing Enter or opening the full
/// results: searched without the pause.
class SearchSubmitted extends _SearchQueryEvent {
  final String query;

  const SearchSubmitted(this.query);

  @override
  List<Object> get props => [query];
}

/// Sync the drives search could not look inside, then search again.
class SearchSyncRequested extends SearchEvent {
  const SearchSyncRequested();
}

/// A sync finished, so the newest query is searched again: the drives it
/// walked can be searched now.
class _SearchRerun extends _SearchQueryEvent {
  const _SearchRerun();
}

/// Something changed which drives count, or whether a sync is covering them:
/// the drives table, the hide toggle, or a sync starting or stopping.
class _SearchCoverageChanged extends SearchEvent {
  const _SearchCoverageChanged();
}
