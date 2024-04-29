import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';

abstract class SearchRepository {
  Future<List<SearchResult>> search(String query);
}

class ArDriveSearchRepository implements SearchRepository {
  final DriveDao _driveDao;

  ArDriveSearchRepository(this._driveDao);

  @override
  Future<List<SearchResult>> search(String query) async {
    if (query.isEmpty) return Future.value([]);

    String sanitizedQuery = query.trim().toLowerCase();

    SearchQueryType queryType = _getQueryType(sanitizedQuery);

    if (queryType != SearchQueryType.name) {
      sanitizedQuery = sanitizedQuery.split(':').last.trim().toLowerCase();
      // removes white spaces
      sanitizedQuery = sanitizedQuery.replaceAll(' ', '');
    }

    return _driveDao.search(query: sanitizedQuery, type: queryType);
  }

  SearchQueryType _getQueryType(String query) {
    if (query.startsWith('id:')) {
      return SearchQueryType.uuid;
    } else if (query.startsWith('txId')) {
      return SearchQueryType.txId;
    } else {
      return SearchQueryType.name;
    }
  }
}
