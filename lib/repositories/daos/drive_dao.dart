import 'package:moor/moor.dart';

import '../database.dart';
import '../models/models.dart';

part 'drive_dao.g.dart';

@UseDao(tables: [Drives, FolderEntries])
class DriveDao extends DatabaseAccessor<Database> with _$DriveDaoMixin {
  DriveDao(Database db) : super(db);

  Stream<Drive> watchDrive(String driveId) =>
      (select(drives)..where((d) => d.id.equals(driveId))).watchSingle();

  Stream<FolderEntry> watchFolder(String folderId) =>
      (select(folderEntries)..where((f) => f.id.equals(folderId)))
          .watchSingle();
}
