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

        batch.insert(
          folderEntries,
          FolderEntriesCompanion(
            id: Value('345'),
            name: Value('Documents'),
            path: Value('/Documents'),
            items: Value([]),
          ),
        );
      });
}
