import 'package:ardrive/entities/entities.dart';
import 'package:moor/moor.dart';

import 'models.dart';

@DataClassName('FolderRevision')
class FolderRevisions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get folderId => text()();
  TextColumn get driveId => text().customConstraint('REFERENCES drives(id)')();

  TextColumn get name => text().withLength(min: 1)();
  TextColumn get parentFolderId => text().nullable()();

  TextColumn get metadataTxId => text()();

  /// The date on which this revision was created.
  DateTimeColumn get dateCreated =>
      dateTime().clientDefault(() => DateTime.now())();

  TextColumn get action => text()();
}

extension FolderRevisionExtensions on FolderRevisionsCompanion {
  /// Converts the revision to an instance of [FolderEntriesCompanion].
  ///
  /// This instance will lack a proper path and `dateCreated`.
  FolderEntriesCompanion toEntryCompanion() => FolderEntriesCompanion.insert(
        id: folderId.value,
        driveId: driveId.value,
        parentFolderId: parentFolderId,
        name: name.value,
        path: '',
        lastUpdated: dateCreated,
      );
}

extension FolderEntityExtensions on FolderEntity {
  /// Returns the action performed on the folder that lead to the new revision.
  String getPerformedRevisionAction(
      [FolderRevisionsCompanion previousRevision]) {
    if (previousRevision == null) {
      return RevisionAction.create;
    } else if (name != previousRevision.name.value) {
      return RevisionAction.rename;
    } else if (parentFolderId != previousRevision.parentFolderId.value) {
      return RevisionAction.move;
    }

    return null;
  }
}
