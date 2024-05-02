import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/search/search_result.dart';

abstract class SearchRepository {
  Future<List<SearchResult>> search(String query);
}

class ArDriveSearchRepository implements SearchRepository {
  final DriveDao _driveDao;

  ArDriveSearchRepository(this._driveDao);

  @override
  Future<List<SearchResult>> search(String query) async {
    if (query.isEmpty) return Future.value([]);

    String sanitizedQuery = query.toLowerCase();

    return _driveDao.search(query: sanitizedQuery, type: SearchQueryType.name);
  }
}
