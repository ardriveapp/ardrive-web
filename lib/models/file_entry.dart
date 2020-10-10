import 'package:ardrive/entities/entities.dart';
import 'package:moor/moor.dart';

import './database/database.dart';

@DataClassName('FileEntry')
class FileEntries extends Table {
  TextColumn get id => text()();
  TextColumn get driveId => text().customConstraint('REFERENCES drives(id)')();
  TextColumn get parentFolderId =>
      text().customConstraint('REFERENCES folderEntries(id)')();

  TextColumn get name => text().withLength(min: 1)();
  TextColumn get path => text()();

  TextColumn get dataTxId => text()();

  IntColumn get size => integer()();

  /// Whether or not this file has been uploaded and been mined onto the blockweave.
  BoolColumn get ready => boolean()();

  // DateTimeColumn get dateCreated => dateTime().nullable()();
  // DateTimeColumn get dateUpdated => dateTime().nullable()();

  DateTimeColumn get lastModifiedDate => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
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
