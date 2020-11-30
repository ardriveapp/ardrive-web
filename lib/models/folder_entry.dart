import 'package:ardrive/entities/entities.dart';
import 'package:moor/moor.dart';

import './database/database.dart';

@DataClassName('FolderEntry')
class FolderEntries extends Table {
  TextColumn get id => text()();
  TextColumn get driveId => text()();

  TextColumn get name => text().withLength(min: 1)();
  TextColumn get parentFolderId => text().nullable()();
  TextColumn get path => text()();

  DateTimeColumn get dateCreated =>
      dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get lastUpdated =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id, driveId};
}

extension FolderEntryExtensions on FolderEntry {
  FolderEntity asEntity() => FolderEntity(
        id: id,
        driveId: driveId,
        parentFolderId: parentFolderId,
        name: name,
      );
}
