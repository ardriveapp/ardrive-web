import 'package:moor/moor.dart';

import '../models.dart';
import 'shared.dart';

part 'database.g.dart';

@UseMoor(
  tables: [
    Drives,
    FolderEntries,
    FolderRevisions,
    FileEntries,
    FileRevisions,
    Profiles,
  ],
  daos: [DrivesDao, DriveDao, ProfileDao],
)
class Database extends _$Database {
  Database([QueryExecutor e]) : super(e ?? openConnection());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) {
          return m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from == 1 || from == 2) {
            // Reset the database.
            for (final table in allTables) {
              await m.deleteTable(table.actualTableName);
            }

            await m.createAll();
          }
        },
      );
}
