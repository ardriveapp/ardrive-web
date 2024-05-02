part of 'search_bloc.dart';

sealed class SearchState extends Equatable {
  const SearchState();

  @override
  List<Object> get props => [];
}

final class SearchInitial extends SearchState {}

final class SearchEmpty extends SearchState {}

final class SearchQueryEmpty extends SearchState {}

final class SearchSuccess extends SearchState {
  final List<SearchResult> results;

  const SearchSuccess(this.results);

  @override
  List<Object> get props => [results];
}
