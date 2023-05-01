import 'package:drift/drift.dart';

Future<void> onUpgradeV16ToV17(
  Iterable<TableInfo<Table, dynamic>> allTables,
  Migrator m,
  int from,
  int to,
) async {
  if (from == 16 && to == 17) {
    final driveRevisionsTable = allTables.firstWhere(
      (element) => element.actualTableName == 'drive_revisions',
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
  } else {
    throw Exception('Asked to migrate v16 -> v17, but got v$from -> v$to');
  }
}
