import 'package:moor/moor.dart';

import '../models.dart';
import 'unsupported.dart'
    if (dart.library.html) 'web.dart'
    if (dart.library.io) 'ffi.dart';

part 'database.g.dart';

@UseMoor(
  include: {'../tables/all.moor'},
  daos: [DriveDao, ProfileDao],
)
class Database extends _$Database {
  Database([QueryExecutor e]) : super(e ?? openConnection());

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) {
          return m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from == 1 || from == 2 || from == 3 || from == 4) {
            // Reset the database.
            for (final table in allTables) {
              await m.deleteTable(table.actualTableName);
            }

            await m.createAll();
          }
        },
      );

  void a() {}
}
