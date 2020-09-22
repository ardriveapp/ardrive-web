import 'package:moor/moor.dart';

import '../models.dart';
import 'shared.dart';

part 'database.g.dart';

@UseMoor(
    tables: [Drives, FolderEntries, FileEntries], daos: [DrivesDao, DriveDao])
class Database extends _$Database {
  Database() : super(openConnection());

  @override
  int get schemaVersion => 1;
}
