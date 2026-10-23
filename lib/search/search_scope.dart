import 'package:ardrive/arns/data/arns_dao.dart';
import 'package:ardrive/blocs/hide/global_hide_bloc.dart';
import 'package:ardrive/core/arfs/repository/file_repository.dart';
import 'package:ardrive/core/arfs/repository/folder_repository.dart';
import 'package:ardrive/library/data/library_search_repository.dart';
import 'package:ardrive/library/domain/library_mode.dart';
import 'package:ardrive/library/presentation/library_loader/library_loader_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/search/domain/bloc/search_bloc.dart';
import 'package:ardrive/search/domain/repository/search_repository.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The text being searched for and the search itself, for one signed-in
/// session.
///
/// Every search field in the session edits [controller], and the search
/// follows it, so the box at the top of the page, its dropdown and the full
/// results always agree on the query and run it once.
class SearchSession {
  SearchSession(this.bloc) {
    controller.addListener(_onTextChanged);
  }

  final SearchBloc bloc;
  final controller = TextEditingController();

  String _lastQuery = '';

  /// Set by a search box taken down while it had focus, which the explorer
  /// does whenever the drive on screen changes state. The box built in its
  /// place takes focus back, so the reader's dropdown stays open.
  bool restoreBoxFocus = false;

  /// The query as searched: the field's text without the spaces around it.
  String get query => controller.text.trim();

  void _onTextChanged() {
    // The controller also notifies when only the caret or the selection
    // moves; that is not a new query.
    final query = this.query;

    if (query == _lastQuery) {
      return;
    }

    _lastQuery = query;
    bloc.add(SearchQueryChanged(query));
  }

  /// Searches the current text now, without the pause typing waits for.
  void submit() {
    _lastQuery = query;
    bloc.add(SearchSubmitted(query));
  }

  /// Empties the field, after the reader has gone to a result.
  void clear() => controller.clear();

  /// Stops following the text. The controller is left to be collected rather
  /// than disposed: a search dialog open at logout keeps its field, and a field
  /// on a disposed controller throws.
  void dispose() {
    controller.removeListener(_onTextChanged);
  }
}

/// Provides the session's [SearchSession] and its [SearchBloc] to everything
/// below, the app's navigator included, so dialogs can reach them too.
///
/// It sits above the pages rather than in a search box because the boxes come
/// and go: the explorer builds its top bar afresh for each state of the drive
/// on screen, and a sync started from one box finishes under another.
class SearchScope extends StatefulWidget {
  const SearchScope({super.key, required this.child});

  final Widget child;

  @override
  State<SearchScope> createState() => _SearchScopeState();
}

class _SearchScopeState extends State<SearchScope> {
  late final SearchSession _session;

  @override
  void initState() {
    super.initState();

    _session = SearchSession(
      SearchBloc(
        LibraryMode.isOn ? _librarySearch() : _appSearch(),
        syncCubit: context.read<SyncCubit>(),
        globalHideBloc: context.read<GlobalHideBloc>(),
      ),
    );
  }

  SearchRepository _appSearch() => ArDriveSearchRepository(
        context.read<DriveDao>(),
        ARNSDao(context.read<Database>()),
        context.read<FileRepository>(),
        context.read<FolderRepository>(),
      );

  /// A library page searches only its library, once it is open.
  SearchRepository _librarySearch() {
    final loader = context.read<LibraryLoaderCubit>();
    return LibrarySearchRepository(
      context.read<DriveDao>(),
      config: () => switch (loader.state) {
        LibraryReady(:final config) => config,
        _ => null,
      },
    );
  }

  @override
  void dispose() {
    _session.dispose();
    _session.bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider<SearchSession>.value(
      value: _session,
      child: BlocProvider<SearchBloc>.value(
        value: _session.bloc,
        child: widget.child,
      ),
    );
  }
}
