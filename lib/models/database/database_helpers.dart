import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/utils/logger.dart';

class DatabaseHelpers {
  final Database _db;

  DatabaseHelpers(this._db);

  Future<void> deleteAllTables() async {
    try {
      logger.d('Deleting all tables');
      await _db.transaction(() async {
        for (final table in _db.allTables) {
          await _db.delete(table).go();
        }
      });
    } catch (e) {
      logger.e('Error deleting all tables', e);
    }
  }

  /// Drops what the signed-in session kept in memory rather than in a table -
  /// drive keys and recently previewed bytes. Logout needs both this and
  /// [deleteAllTables]: the tables go, and so must what was read out of them.
  ///
  /// Unlike [deleteAllTables], a failure here is not swallowed. A logout that
  /// reported success with drive keys still in memory would be the one outcome
  /// worse than a logout that says it failed.
  Future<void> clearSessionMemory() async {
    try {
      await _db.driveDao.clearSessionMemory();
    } catch (e) {
      logger.e('Error clearing session memory', e);
      rethrow;
    }
  }
}
