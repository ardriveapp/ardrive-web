import 'package:moor/moor.dart';

import '../database.dart';
import '../models/models.dart';

part 'drives_dao.g.dart';

@UseDao(tables: [Drives, FolderEntries])
class DrivesDao extends DatabaseAccessor<Database> with _$DrivesDaoMixin {
  DrivesDao(Database db) : super(db);

  Stream<List<Drive>> watchAllDrives() => select(drives).watch();

  Future<void> createDrive({@required String name}) => batch((batch) {
        batch.insert(
          drives,
          DrivesCompanion(
            id: Value(name),
            name: Value(name),
            rootFolderId: Value('345'),
          ),
        );

        batch.insertAll(
          folderEntries,
          [
            FolderEntriesCompanion(
              id: Value('345'),
              driveId: Value(name),
              name: Value('Personal'),
              path: Value('/Personal'),
            ),
            FolderEntriesCompanion(
              id: Value('567'),
              driveId: Value(name),
              parentFolderId: Value('345'),
              name: Value('Documents'),
              path: Value('/Personal/Documents'),
            ),
            FolderEntriesCompanion(
              id: Value('981'),
              driveId: Value(name),
              parentFolderId: Value('345'),
              name: Value('Pictures'),
              path: Value('/Personal/Pictures'),
            ),
            FolderEntriesCompanion(
              id: Value('789'),
              driveId: Value(name),
              parentFolderId: Value('567'),
              name: Value('Resumes'),
              path: Value('/Personal/Documents/Resumes'),
            )
          ],
        );
      });
}
