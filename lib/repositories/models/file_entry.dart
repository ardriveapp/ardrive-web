import 'package:moor/moor.dart';

@DataClassName('FileEntry')
class FileEntries extends Table {
  TextColumn get id => text()();
  TextColumn get driveId => text().customConstraint('REFERENCES drives(id)')();
  TextColumn get parentFolderId =>
      text().customConstraint('REFERENCES folderEntries(id)')();

  TextColumn get name => text().withLength(min: 1)();
  TextColumn get path => text().withLength(min: 1)();

  DateTimeColumn get dateCreated => dateTime()();
  DateTimeColumn get dateUpdated => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
