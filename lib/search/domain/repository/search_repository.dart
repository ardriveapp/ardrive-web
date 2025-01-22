import 'package:ardrive/arns/data/arns_dao.dart';
import 'package:ardrive/core/arfs/repository/file_repository.dart';
import 'package:ardrive/core/arfs/repository/folder_repository.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/search/search_result.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ario_sdk/ario_sdk.dart';

abstract class SearchRepository {
  Future<List<SearchResult>> search(String query);
}

class ArDriveSearchRepository implements SearchRepository {
  final DriveDao _driveDao;
  final ARNSDao _arnsDao;
  final FileRepository _fileRepository;
  final FolderRepository _folderRepository;

  ArDriveSearchRepository(this._driveDao, this._arnsDao, this._fileRepository,
      this._folderRepository);

  @override
  Future<List<SearchResult>> search(String query) async {
    logger.d('Searching for $query');
    final startTime = DateTime.now();

    if (query.isEmpty) return Future.value([]);

    String sanitizedQuery = query.toLowerCase();

    // Start both searches in parallel
    final arnsSearchFuture = _searchArns(query);
    final driveSearchFuture =
        _driveDao.search(query: sanitizedQuery, type: SearchQueryType.all);

    // Wait for both searches to complete
    final results = await Future.wait([arnsSearchFuture, driveSearchFuture]);

    // Combine results and handle duplicates
    final List<SearchResult> allResults = [...?results[0], ...results[1] ?? []];

    final Map<String, SearchResult> uniqueResults = {};
    final List<SearchResult> duplicates = [];

    // Process results to identify duplicates
    for (var result in allResults) {
      if (uniqueResults.containsKey(result.uniqueId)) {
        // This is a duplicate - mark it and keep track of the original
        duplicates.add(result.asDuplicate());
      } else {
        uniqueResults[result.uniqueId] = result;
      }
    }

    // Combine unique results and duplicates, with duplicates at the end
    final List<SearchResult> combinedResults = [
      ...uniqueResults.values,
      ...duplicates,
    ];

    final endTime = DateTime.now();
    final duration = endTime.difference(startTime);
    logger.d('Search completed in ${duration.inMilliseconds}ms');

    return combinedResults;
  }

  Future<List<SearchResult>?> _searchArns(String query) async {
    final splitDomainAndName = extractNameAndDomain(query);

    final arnsRecord = await _arnsDao
        .getActiveARNSRecordByName(
            domain: splitDomainAndName['domain'] ?? '',
            name: splitDomainAndName['name'] ?? '@')
        .getSingleOrNull();

    if (arnsRecord == null) return null;

    final file = await _fileRepository.getFileEntryById(arnsRecord.fileId);
    final drive = await _driveDao.driveById(driveId: file.driveId).getSingle();
    final parentFolder =
        await _folderRepository.getFolderEntryById(file.parentFolderId);

    return [
      SearchResult(
        drive: drive,
        result: file,
        parentFolder: parentFolder,
        hasArNSName: true,
      )
    ];
  }
}
