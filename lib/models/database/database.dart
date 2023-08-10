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
          return m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          logger.i('schema changed from $from to $to ');

          if (from == 16 && to == 17) {
            // Then we're adding the pin and custom fields columns
            logger.i('Migrating schema from v16 to v17');

            final driveRevisionsTable = allTables.firstWhere(
              (element) => element.actualTableName == 'drive_revisions',
            );
            final folderRevisionsTable = allTables.firstWhere(
              (element) => element.actualTableName == 'folder_revisions',
            );
            final fileRevisionsTable = allTables.firstWhere(
              (element) => element.actualTableName == 'file_revisions',
            );

            await m.alterTable(
              TableMigration(
                driveRevisionsTable,
                newColumns: [
                  GeneratedColumn(
                    'customJsonMetadata',
                    'drive_revisions',
                    true,
                    type: DriftSqlType.string,
                    defaultValue: null,
                    clientDefault: null,
                  ),
                  GeneratedColumn(
                    'customGQLTags',
                    'drive_revisions',
                    true,
                    type: DriftSqlType.string,
                    defaultValue: null,
                    clientDefault: null,
                  ),
                ],
              ),
            );

            await m.alterTable(
              TableMigration(
                folderRevisionsTable,
                newColumns: [
                  GeneratedColumn(
                    'customJsonMetadata',
                    'folder_revisions',
                    true,
                    type: DriftSqlType.string,
                    defaultValue: null,
                    clientDefault: null,
                  ),
                  GeneratedColumn(
                    'customGQLTags',
                    'folder_revisions',
                    true,
                    type: DriftSqlType.string,
                    defaultValue: null,
                    clientDefault: null,
                  ),
                ],
              ),
            );

            await m.alterTable(
              TableMigration(
                fileRevisionsTable,
                newColumns: [
                  GeneratedColumn(
                    'customJsonMetadata',
                    'file_revisions',
                    true,
                    type: DriftSqlType.string,
                    defaultValue: null,
                    clientDefault: null,
                  ),
                  GeneratedColumn(
                    'customGQLTags',
                    'file_revisions',
                    true,
                    type: DriftSqlType.string,
                    defaultValue: null,
                    clientDefault: null,
                  ),
                  GeneratedColumn(
                    'pinnedDataOwnerAddress',
                    'file_revisions',
                    true,
                    type: DriftSqlType.string,
                    defaultValue: null,
                    clientDefault: null,
                  ),
                ],
              ),
            );
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
