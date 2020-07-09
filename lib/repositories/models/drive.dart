import 'package:moor/moor.dart';

enum DrivePrivacy { publicReadOnly, private }

class Drives extends Table {
  TextColumn get id => text()();
  TextColumn get rootFolderId =>
      text().nullable().customConstraint('REFERENCES folderEntries(id)')();
  TextColumn get name => text().withLength(min: 1)();

  @override
  Set<Column> get primaryKey => {id};
}
