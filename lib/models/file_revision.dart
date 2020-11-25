import 'package:ardrive/entities/entities.dart';
import 'package:moor/moor.dart';

import 'models.dart';

@DataClassName('FileRevision')
class FileRevisions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get fileId => text()();
  TextColumn get driveId => text().customConstraint('REFERENCES drives(id)')();
  TextColumn get parentFolderId => text()();

  TextColumn get name => text().withLength(min: 1)();
  IntColumn get size => integer()();
  DateTimeColumn get lastModifiedDate => dateTime()();

  TextColumn get metadataTxId => text()();
  TextColumn get dataTxId => text()();

  /// The date on which this revision was created.
  DateTimeColumn get dateCreated =>
      dateTime().clientDefault(() => DateTime.now())();

  TextColumn get action => text()();
}

extension FileRevisionExtensions on FileRevisionsCompanion {
  /// Converts the revision to an instance of [FileEntriesCompanion].
  ///
  /// This instance will lack a proper path and `dateCreated`.
  FileEntriesCompanion toEntryCompanion() => FileEntriesCompanion.insert(
        id: fileId.value,
        driveId: driveId.value,
        parentFolderId: parentFolderId.value,
        name: name.value,
        dataTxId: dataTxId.value,
        size: size.value,
        path: '',
        lastUpdated: dateCreated,
        lastModifiedDate: lastModifiedDate.value,
      );
}

extension FileEntityExtensions on FileEntity {
  /// Returns the action performed on the file that lead to the new revision.
  String getPerformedRevisionAction([FileRevisionsCompanion previousRevision]) {
    if (previousRevision == null) {
      return RevisionAction.create;
    } else if (name != previousRevision.name.value) {
      return RevisionAction.rename;
    } else if (parentFolderId != previousRevision.parentFolderId.value) {
      return RevisionAction.move;
    } else if (dataTxId != previousRevision.dataTxId.value) {
      return RevisionAction.uploadNewVersion;
    }

    return null;
  }
}
