import 'package:moor/moor.dart';

import '../database.dart';
import '../models/models.dart';

part 'drives_dao.g.dart';

@UseDao(tables: [Drives, FolderEntries])
class DrivesDao extends DatabaseAccessor<Database> with _$DrivesDaoMixin {
  DrivesDao(Database db) : super(db);

  Stream<List<Drive>> watchAllDrives() => select(drives).watch();

  Future<void> createDrive({@required String name}) => batch((batch) {
        final driveId = name;
        final rootFolderId = name;

        batch.insert(
          drives,
          DrivesCompanion(
            id: Value(driveId),
            name: Value(name),
            rootFolderId: Value(rootFolderId),
          ),
        );

        batch.insert(
          folderEntries,
          FolderEntriesCompanion(
            id: Value(rootFolderId),
            driveId: Value(driveId),
            name: Value(name),
            path: Value('/$name'),
          ),
        );
      });
}
