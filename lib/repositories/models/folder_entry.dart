import 'package:moor/moor.dart';

@DataClassName('FolderEntry')
class FolderEntries extends Table {
  TextColumn get id => text()();
  TextColumn get driveId => text().customConstraint('REFERENCES drives(id)')();
  TextColumn get parentFolderId =>
      text().nullable().customConstraint('REFERENCES folderEntries(id)')();

  TextColumn get name => text().withLength()();
  TextColumn get path => text().withLength()();

  @override
  Set<Column> get primaryKey => {id};
}
