import 'package:ardrive/utils/logger/logger.dart';
import 'package:drift/drift.dart';

Future<void> onUpgradeDefault(
  Iterable<TableInfo<Table, dynamic>> allTables,
  Migrator m,
  int from,
  int to,
) async {
  if (from >= 1 && from < to) {
    logger.w(
      'WARNING: Fallbacking to default DB migration: drop and re-create all'
      ' tables - from v$from to v$to',
    );

    // Reset the database.
    for (final table in allTables) {
      await m.deleteTable(table.actualTableName);
    }

    await m.createAll();
  }
}
