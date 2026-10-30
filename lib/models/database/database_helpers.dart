import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/utils/logger.dart';

class DatabaseHelpers {
  final Database _db;

  DatabaseHelpers(this._db);

  DriveDao get driveDao => _db.driveDao;

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

  /// What sign-out does to the device after [deleteAllTables], so nothing the
  /// profile held can be read back from storage (docs/WEB_DATABASE.md,
  /// "Signing out"):
  ///
  /// 1. `VACUUM`: the file is rebuilt without its free pages, which still
  ///    hold whatever was deleted before `secure_delete` was on.
  /// 2. On the web, the tab that owns the database deletes the copies older
  ///    builds left: the sql.js and #2197 IndexedDB stores and any
  ///    `ardrive-reset-<time>` copy.
  ///
  /// Never throws: the user is already signed out. Returns what step 2
  /// deleted.
  Future<List<String>> wipeAfterSignOut() async {
    try {
      await _db.vacuum();
    } catch (e) {
      logger.w('Could not vacuum the database after sign-out: $e');
    }
    try {
      return await Database.deleteLegacyStores();
    } catch (e) {
      logger.w('Could not delete older stores after sign-out: $e');
      return const [];
    }
  }

  /// Deletes every copy of the profile in the format before 3.0 that this
  /// device may still hold, once the profile is in the current format:
  ///
  /// 1. The older database stores and `ardrive-reset-<time>` copies, each of
  ///    which holds a format 1 profile ([Database.deleteLegacyStores]).
  /// 2. `VACUUM`, which drops the free pages the rewritten profile row left,
  ///    and any from before `secure_delete` was on.
  ///
  /// A format 1 profile leaks the start of the wallet's JSON to anyone who
  /// reads it (see [currentProfileFormat]), so this gives up the rollback
  /// safety net the older stores were kept for (docs/WEB_DATABASE.md §4).
  ///
  /// Once per profile, and only in the tab that owns the database; a failure
  /// leaves it to the next session. Never throws. Returns whether it ran.
  Future<bool> clearOlderCopies({
    Future<List<String>> Function()? deleteStores,
    bool? ownsDatabase,
  }) async {
    try {
      if (!(ownsDatabase ?? Database.ownsDatabase)) return false;
      if (!await _db.profileDao.needsOlderCopiesCleared()) return false;
      await (deleteStores ?? Database.deleteLegacyStores)();
      await _db.vacuum();
      await _db.profileDao.markOlderCopiesCleared();
      logger.i('Cleared the older copies of the profile on this device');
      return true;
    } catch (e) {
      logger.w('Could not clear the older copies of the profile; next '
          'session tries again: ${e.runtimeType}');
      return false;
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
