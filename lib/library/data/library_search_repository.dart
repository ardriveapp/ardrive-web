import 'package:ardrive/library/domain/library_config.dart';
import 'package:ardrive/library/domain/library_scope.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/search/domain/repository/search_repository.dart';
import 'package:ardrive/search/domain/search_coverage.dart';
import 'package:ardrive/search/search_result.dart';

/// Search on a library page: finds only what the library shows.
///
/// The snapshot holds the whole drive, hidden items and, for a folder
/// library, every folder its owner did not publish. The app's search would
/// list all of them, and the drive itself by name. This lists the files and
/// folders [LibraryContents] shows, never the drive, and never the published
/// folder itself, whose result would name the folder above it.
///
/// There is one drive, already here in full, so search covers everything and
/// nothing ever changes underneath it.
class LibrarySearchRepository implements SearchRepository {
  LibrarySearchRepository(
    this._driveDao, {
    required LibraryConfig? Function() config,
  }) : _config = config;

  final DriveDao _driveDao;

  /// The open library, or null while it is still loading.
  final LibraryConfig? Function() _config;

  LibraryConfig? _contentsConfig;
  Future<LibraryContents>? _contents;

  /// Results kept of each kind, as many as the app's search keeps.
  static const resultsPerKind = 50;

  /// Rows read per query. The queries match the whole drive, so for a folder
  /// library most rows can be outside it; reading on past them, a page at a
  /// time, keeps those from crowding out the matches inside.
  static const _page = 200;

  /// How far to read on: a folder of a large drive, searched for a common
  /// letter, stops here rather than reading the drive's every name.
  static const _maxPages = 25;

  @override
  Future<List<SearchResult>> search(String query) async {
    final config = _config();
    if (config == null || query.isEmpty) return const [];
    final contents = await _contentsOf(config);

    bool shows(SearchResult result) {
      final item = result.result;
      if (item is FolderEntry) {
        return item.id != config.scopeRootFolderId &&
            contents.showsFolder(item.id);
      }
      if (item is FileEntry) return contents.showsFile(item.id);
      return false;
    }

    final found = await Future.wait([
      _searchKind(query, SearchQueryType.folders, shows),
      _searchKind(query, SearchQueryType.files, shows),
    ]);
    return rankSearchResults(query, found.expand((kind) => kind));
  }

  Future<List<SearchResult>> _searchKind(
    String query,
    SearchQueryType type,
    bool Function(SearchResult) shows,
  ) async {
    final kept = <SearchResult>[];
    for (var page = 0; page < _maxPages; page++) {
      final rows = await _driveDao.search(
        query: query,
        type: type,
        limit: _page,
        offset: page * _page,
      );
      for (final row in rows) {
        if (!shows(row)) continue;
        kept.add(row);
        if (kept.length == resultsPerKind) return kept;
      }
      if (rows.length < _page) break;
    }
    return kept;
  }

  Future<LibraryContents> _contentsOf(LibraryConfig config) {
    if (!identical(config, _contentsConfig)) {
      _contentsConfig = config;
      _contents = LibraryContents.load(_driveDao, config);
    }
    return _contents!;
  }

  @override
  Future<SearchCoverage> coverage({required bool includeHiddenDrives}) async =>
      _config() == null
          ? SearchCoverage.unknown
          : const SearchCoverage(totalDrives: 1);

  @override
  Stream<void> watchDrives() => const Stream.empty();
}
