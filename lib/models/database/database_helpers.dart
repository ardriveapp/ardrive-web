import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/utils/logger.dart';

class DatabaseHelpers {
  final Database _db;

  DatabaseHelpers(this._db);

  Future<void> deleteAllTables() async {
    try {
      logger.d('Deleting all tables');
      await _db.transaction(
        () async {
          for (final table in _db.allTables) {
            await _db.delete(table).go();
          }
        },
      );
    } catch (e) {
      logger.e('Error deleting all tables', e);
    }
  }
}
