import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:drift/drift.dart';

import 'unsupported.dart'
    if (dart.library.html) 'web.dart'
    if (dart.library.io) 'ffi.dart';

part 'database.g.dart';

@DriftDatabase(
  include: {'../tables/all.drift'},
  daos: [DriveDao, ProfileDao],
)
class Database extends _$Database {
  Database([QueryExecutor? e]) : super(e ?? openConnection());

  @override
  int get schemaVersion => 17;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) {
          logger.i('creating database schema');
          return m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          logger.i('schema changed from $from to $to ');

          if (from == 16 && to == 17) {
            // Then we're adding the pin and custom fields columns
            logger.i('Migrating schema from v16 to v17');

            await m.addColumn(
              driveRevisions,
              driveRevisions.customJsonMetadata,
            );
            await m.addColumn(driveRevisions, driveRevisions.customGQLTags);
            await m.addColumn(drives, drives.customJsonMetadata);
            await m.addColumn(drives, drives.customGQLTags);

            await m.addColumn(
              folderRevisions,
              folderRevisions.customJsonMetadata,
            );
            await m.addColumn(folderRevisions, folderRevisions.customGQLTags);
            await m.addColumn(folderEntries, folderEntries.customJsonMetadata);
            await m.addColumn(folderEntries, folderEntries.customGQLTags);

            await m.addColumn(fileRevisions, fileRevisions.customJsonMetadata);
            await m.addColumn(fileRevisions, fileRevisions.customGQLTags);
            await m.addColumn(fileEntries, fileEntries.customJsonMetadata);
            await m.addColumn(fileEntries, fileEntries.customGQLTags);
          } else if (from >= 1 && from < schemaVersion) {
            // Reset the database.
            for (final table in allTables) {
              await m.deleteTable(table.actualTableName);
            }

            await m.createAll();
          }
        },
      );
}
