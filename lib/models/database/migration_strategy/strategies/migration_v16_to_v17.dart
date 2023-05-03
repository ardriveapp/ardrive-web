import 'package:ardrive/utils/logger/logger.dart';
import 'package:drift/drift.dart';

Future<void> onUpgradeV16ToV17(
  Iterable<TableInfo<Table, dynamic>> allTables,
  Migrator m,
  int from,
  int to,
) async {
  if (from == 16 && to == 17) {
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
          GeneratedColumn<String?>(
            'customJsonMetaData',
            'drive_revisions',
            true,
            type: const StringType(),
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
          GeneratedColumn<String?>(
            'customJsonMetaData',
            'folder_revisions',
            true,
            type: const StringType(),
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
          GeneratedColumn<String?>(
            'customJsonMetaData',
            'file_revisions',
            true,
            type: const StringType(),
            defaultValue: null,
            clientDefault: null,
          ),
        ],
      ),
    );
  } else {
    throw Exception('Asked to migrate v16 -> v17, but got v$from -> v$to');
  }
}
