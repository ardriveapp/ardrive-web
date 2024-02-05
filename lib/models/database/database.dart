import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/utils/logger.dart';
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
          logger.d('creating database schema');
          return m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          logger.d('schema changed from $from to $to');

          if (from >= 1 && from < 16) {
            logger.w(
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
              logger.d('Migrating schema from v16 to v17');

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
            } else if (from == 17 && to == 18) {
              // Then we're adding the isHidden column
              logger.i('Migrating schema from v17 to v18');

              await m.addColumn(folderRevisions, folderRevisions.isHidden);
              await m.addColumn(fileRevisions, fileRevisions.isHidden);

              await m.addColumn(folderEntries, folderEntries.isHidden);
              await m.addColumn(fileEntries, fileEntries.isHidden);
            }
            if (from < 18) {
              // TODO: Merge with PE-4727
              // Adding support for remembering source Ethereum address
              logger.d('RESERVED: Migrating schema from v17 to v18');
            }
            if (from < 19) {
              // Adding licenses
              logger.d('Migrating schema from v18 to v19');

              await m.createTable(licenses);

              await m.addColumn(fileEntries, fileEntries.licenseTxId);
              await m.addColumn(fileRevisions, fileRevisions.licenseTxId);
            }
          }
        },
      );
}
