import 'package:ardrive/utils/logger/logger.dart';
import 'package:drift/drift.dart';

Future<void> onUpgradeV16ToV17(
  Iterable<TableInfo<Table, dynamic>> allTables,
  Migrator m,
  int from,
  int to,
) async {
  logger.i('Migrating schema from v16 to v17');
  throw UnimplementedError('TODO: implement migration from v16 to v17');
}
