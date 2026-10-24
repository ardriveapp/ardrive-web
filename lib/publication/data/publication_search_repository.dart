import 'package:ardrive/publication/domain/publication_config.dart';
import 'package:ardrive/publication/domain/publication_scope.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/search/domain/repository/search_repository.dart';
import 'package:ardrive/search/domain/search_coverage.dart';
import 'package:ardrive/search/search_result.dart';

/// Search on a publication: finds only what the publication shows.
///
/// The snapshot holds the whole drive, hidden items and, for a folder
/// publication, every folder its owner did not publish. The app's search would
/// list all of them, and the drive itself by name. This lists the files and
/// folders [PublicationContents] shows, never the drive, and never the published
/// folder itself, whose result would name the folder above it.
///
/// Results are placed in the publication, not the drive (see [_located]).
///
/// There is one drive, already here in full, so search covers everything and
/// nothing ever changes underneath it.
class PublicationSearchRepository implements SearchRepository {
  PublicationSearchRepository(
    this._driveDao, {
    required PublicationConfig? Function() config,
  }) : _config = config;

  final DriveDao _driveDao;

  /// The open publication, or null while it is still loading.
  final PublicationConfig? Function() _config;

  PublicationConfig? _contentsConfig;
  Future<PublicationContents>? _contents;

  /// Results kept of each kind, as many as the app's search keeps.
  static const resultsPerKind = 50;

  /// Rows read per query. The queries match the whole drive, so for a folder
  /// publication most rows can be outside it; reading on past them, a page at a
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
    return rankSearchResults(
      query,
      found.expand((kind) => kind).map((result) => _located(result, config)),
    );
  }

  /// [result] placed in the publication rather than the drive: a result names
  /// where it is by its drive, then its folder. The drive's name is the
  /// publication's title, and an item at the publication's root names no folder, so
  /// a folder publication never shows the names above it.
  SearchResult _located(SearchResult result, PublicationConfig config) {
    final parent = result.parentFolder;
    return SearchResult(
      result: result.result,
      drive: result.drive.copyWith(name: config.title),
      parentFolder: parent == null || parent.id == config.scopeRootFolderId
          ? null
          : parent,
      hasArNSName: result.hasArNSName,
      uniqueId: result.uniqueId,
    );
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

  Future<PublicationContents> _contentsOf(PublicationConfig config) {
    if (!identical(config, _contentsConfig)) {
      _contentsConfig = config;
      _contents = PublicationContents.load(_driveDao, config);
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
