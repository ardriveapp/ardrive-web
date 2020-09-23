import 'package:moor/moor.dart';

class Drives extends Table {
  TextColumn get id => text()();
  TextColumn get rootFolderId =>
      text().customConstraint('REFERENCES folderEntries(id)')();

  TextColumn get ownerAddress => text()();

  TextColumn get name => text().withLength(min: 1)();

  /// The latest block we've pulled state from.
  IntColumn get latestSyncedBlock => integer().withDefault(const Constant(0))();

  TextColumn get privacy => text()();

  BlobColumn get encryptedKey => blob().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
