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
  int get schemaVersion => 19;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) {
          logger.i('creating database schema');
          return m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          logger.i('schema changed from $from to $to');

          if (from >= 1 && from < 16) {
            logger.i(
              'No strategy set for migration v$from to v$to'
              ' - Resetting database schema',
            );

            // Reset the database.
            for (final table in allTables) {
              await m.deleteTable(table.actualTableName);
            }

            await m.createAll();
          } else {
            if (from < 17) {
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
              await m.addColumn(
                  folderEntries, folderEntries.customJsonMetadata);
              await m.addColumn(folderEntries, folderEntries.customGQLTags);

              await m.addColumn(
                  fileRevisions, fileRevisions.customJsonMetadata);
              await m.addColumn(fileRevisions, fileRevisions.customGQLTags);
              await m.addColumn(fileEntries, fileEntries.customJsonMetadata);
              await m.addColumn(fileEntries, fileEntries.customGQLTags);

              await m.addColumn(
                  fileEntries, fileEntries.pinnedDataOwnerAddress);
              await m.addColumn(
                fileRevisions,
                fileRevisions.pinnedDataOwnerAddress,
              );
            }
            if (from < 18) {
              // Reserved for PE-4727: Adding support for remembering source Ethereum address
              logger.i('RESERVED: Migrating schema from v17 to v18');
            }
            if (from < 19) {
              // Adding licenses
              logger.i('Migrating schema from v18 to v19');

              await m.addColumn(fileEntries, fileEntries.licenseTxId);
              await m.addColumn(fileRevisions, fileRevisions.licenseTxId);

              await m.createTable(licenses);
            }
          }
        },
      );
}
