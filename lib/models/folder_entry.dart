import 'package:ardrive/entities/entities.dart';
import 'package:moor/moor.dart';

import './database/database.dart';

@DataClassName('FolderEntry')
class FolderEntries extends Table {
  TextColumn get id => text()();
  TextColumn get driveId => text().customConstraint('REFERENCES drives(id)')();
  TextColumn get parentFolderId =>
      text().nullable().customConstraint('REFERENCES folderEntries(id)')();

  TextColumn get name => text().withLength(min: 1)();
  TextColumn get path => text()();

  DateTimeColumn get dateCreated =>
      dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get lastUpdated =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}

extension FolderEntryExtensions on FolderEntry {
  FolderEntity asEntity() => FolderEntity(
        id: id,
        driveId: driveId,
        parentFolderId: parentFolderId,
        name: name,
      );
}
