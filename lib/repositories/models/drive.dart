import 'package:moor/moor.dart';

enum DrivePrivacy { publicReadOnly, private }

class Drives extends Table {
  TextColumn get id => text()();
  TextColumn get rootFolderId =>
      text().customConstraint('REFERENCES folderEntries(id)')();

  TextColumn get owner => text()();

  TextColumn get name => text().withLength(min: 1)();

  /// The latest block we've pulled state from.
  IntColumn get latestSyncedBlock => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
