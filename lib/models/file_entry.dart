import 'package:ardrive/entities/entities.dart';
import 'package:moor/moor.dart';

import './database/database.dart';

@DataClassName('FileEntry')
class FileEntries extends Table {
  TextColumn get id => text()();
  TextColumn get driveId => text().customConstraint('REFERENCES drives(id)')();

  TextColumn get name => text().withLength(min: 1)();
  TextColumn get parentFolderId =>
      text().customConstraint('REFERENCES folderEntries(id)')();
  TextColumn get path => text()();

  IntColumn get size => integer()();
  DateTimeColumn get lastModifiedDate => dateTime()();

  TextColumn get dataTxId => text()();

  DateTimeColumn get dateCreated =>
      dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get lastUpdated =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id, driveId};
}

extension FileEntryExtensions on FileEntry {
  FileEntity asEntity() => FileEntity(
        id: id,
        driveId: driveId,
        parentFolderId: parentFolderId,
        name: name,
        dataTxId: dataTxId,
        size: size,
        lastModifiedDate: lastModifiedDate,
      );
}
