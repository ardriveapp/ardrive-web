import 'package:ardrive/search/domain/repository/search_repository.dart';
import 'package:ardrive/search/search_result.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'search_event.dart';
part 'search_state.dart';

class SearchBloc extends Bloc<SearchEvent, SearchState> {
  final SearchRepository _searchRepository;

  SearchBloc(
    this._searchRepository,
  ) : super(SearchInitial()) {
    on<SearchEvent>((event, emit) async {
      if (event is SearchQueryChanged) {
        if (event.query.isEmpty) {
          emit(SearchQueryEmpty());
        } else {
          final results = await _searchRepository.search(event.query);

          if (results.isEmpty) {
            emit(SearchEmpty());
          } else {
            emit(SearchSuccess(results));
          }
        }
      }
    });
  }
}
