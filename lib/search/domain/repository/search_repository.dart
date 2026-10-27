import 'package:ardrive/arns/data/arns_dao.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/search/domain/search_coverage.dart';
import 'package:ardrive/search/search_result.dart';
import 'package:ardrive/utils/compare_alphabetically_and_natural.dart';
import 'package:ardrive/utils/logger.dart';

abstract class SearchRepository {
  Future<List<SearchResult>> search(String query);

  /// Which drives a search can look inside. See [SearchCoverage].
  ///
  /// [includeHiddenDrives] is whether hidden drives count, which they do only
  /// while hidden items are shown: the reader is not told about drives they
  /// cannot see.
  ///
  /// A drive whose last sync failed still counts as searched when its contents
  /// are here: search did look inside it, and calling it "not synced on this
  /// device" beside results from it would be untrue. A sync the reader asked
  /// for from search that fails says so on its own (`SearchSyncStatus.failed`).
  Future<SearchCoverage> coverage({required bool includeHiddenDrives});

  /// Fires whenever the drives table changes: a drive attached, detached,
  /// hidden, renamed or synced.
  Stream<void> watchDrives();
}

class ArDriveSearchRepository implements SearchRepository {
  final DriveDao _driveDao;

  /// The cache of the ArNS wallet's names, to find files by name; null while
  /// names are off (docs/NAMES.md, Q14).
  final ARNSDao? _arnsDao;

  ArDriveSearchRepository(this._driveDao, {ARNSDao? arnsDao})
      : _arnsDao = arnsDao;

  @override
  Future<List<SearchResult>> search(String query) async {
    logger.d('Searching for $query');
    final startTime = DateTime.now();

    if (query.isEmpty) return Future.value([]);

    final List<SearchResult> allResults = [
      // First, so a file found by its name keeps the name's mark when it is
      // also found by its file name.
      ...await _searchByArNSName(query),
      ...await _driveDao.search(query: query, type: SearchQueryType.all),
    ];

    final Map<String, SearchResult> uniqueResults = {};
    final List<SearchResult> duplicates = [];

    // Process results to identify duplicates
    for (var result in allResults) {
      if (uniqueResults.containsKey(result.uniqueId)) {
        continue;
      } else {
        uniqueResults[result.uniqueId] = result;
      }
    }

    // Combine unique results and duplicates, with duplicates at the end
    final List<SearchResult> combinedResults = [
      ...rankSearchResults(query, uniqueResults.values),
      ...duplicates,
    ];

    final endTime = DateTime.now();
    final duration = endTime.difference(startTime);
    logger.d('Search completed in ${duration.inMilliseconds}ms');

    return combinedResults;
  }

  /// Files a cached name points to, matched on the name as typed in a
  /// browser (`blog_ardrive`), with or without `.ar.io`.
  Future<List<SearchResult>> _searchByArNSName(String query) async {
    final dao = _arnsDao;
    final needle = query.trim().toLowerCase().replaceFirst(
          RegExp(r'\.ar\.io$'),
          '',
        );
    if (dao == null || needle.isEmpty) return [];
    try {
      final escaped = needle
          .replaceAll(r'\', r'\\')
          .replaceAll('%', r'\%')
          .replaceAll('_', r'\_');
      final rows = await dao.filesNamedLike(pattern: '%$escaped%').get();
      final results = <SearchResult>[];
      final seen = <String>{};
      for (final row in rows) {
        if (!seen.add('${row.driveId}_${row.fileId}')) continue;
        final file =
            await _driveDao.fileById(fileId: row.fileId).getSingleOrNull();
        final drive =
            await _driveDao.driveById(driveId: row.driveId).getSingleOrNull();
        if (file == null || drive == null) continue;
        final parent = file.parentFolderId == drive.rootFolderId
            ? null
            : await _driveDao
                .folderById(folderId: file.parentFolderId)
                .getSingleOrNull();
        results.add(SearchResult<FileEntry>(
          result: file,
          drive: drive,
          parentFolder: parent,
          hasArNSName: true,
        ));
      }
      return results;
    } catch (e) {
      logger.w('Could not search names: $e');
      return [];
    }
  }

  @override
  Future<SearchCoverage> coverage({required bool includeHiddenDrives}) async {
    final drives = await _driveDao.searchCoverageDrives().get();
    final inScope =
        drives.where((drive) => includeHiddenDrives || !drive.isHidden);

    return SearchCoverage(
      totalDrives: inScope.length,
      unsearchedDriveIds: [
        for (final drive in inScope)
          if (!drive.hasContents) drive.id,
      ],
    );
  }

  @override
  Stream<void> watchDrives() => _driveDao.allDrives().watch();
}

/// The name a result is listed and matched by.
String searchResultName(SearchResult result) {
  final item = result.result;

  if (item is FileEntry) return item.name;
  if (item is FolderEntry) return item.name;
  if (item is Drive) return item.name;

  return '';
}

/// Orders search results best match first.
///
/// An ArNS name is matched exactly, so it leads, as it did before results were
/// ranked. Then by how the name matches the query, ignoring case: the whole
/// name, then its start, then the start of a word in it, then anywhere. A name
/// matched only through a LIKE wildcard (`%` or `_` in the query) comes last.
/// Ties go to drives, then folders, then files, and then name order. The
/// queries apply the first ranks before their limit (drive_queries.drift), so
/// the best matches survive it.
List<SearchResult> rankSearchResults(
  String query,
  Iterable<SearchResult> results,
) {
  final needle = query.toLowerCase();

  int matchRank(SearchResult result) {
    if (result.hasArNSName ?? false) return 0;

    final name = searchResultName(result).toLowerCase();

    if (name == needle) return 1;
    if (name.startsWith(needle)) return 2;

    final at = name.indexOf(needle);

    if (at < 0) return 5;

    // A word starts after anything that is not a letter or a digit, so
    // "2024 report.pdf", "q3-report" and "annual_report" all start one at
    // "report".
    for (var i = at; i >= 0; i = name.indexOf(needle, i + 1)) {
      if (!_isLetterOrDigit(name.codeUnitAt(i - 1))) return 3;
    }

    return 4;
  }

  int typeRank(SearchResult result) {
    final item = result.result;

    if (item is Drive) return 0;
    if (item is FolderEntry) return 1;

    return 2;
  }

  final ranked = [
    for (final result in results)
      (result: result, match: matchRank(result), type: typeRank(result)),
  ];

  ranked.sort((a, b) {
    final byMatch = a.match.compareTo(b.match);
    if (byMatch != 0) return byMatch;

    final byType = a.type.compareTo(b.type);
    if (byType != 0) return byType;

    return compareAlphabeticallyAndNatural(
      searchResultName(a.result),
      searchResultName(b.result),
    );
  });

  return [for (final entry in ranked) entry.result];
}

bool _isLetterOrDigit(int codeUnit) {
  final char = String.fromCharCode(codeUnit);

  return char.toLowerCase() != char.toUpperCase() ||
      (codeUnit >= 0x30 && codeUnit <= 0x39);
}
