import 'package:drift/drift.dart';

typedef CustomOnUpgrade = Future<void> Function(
  Iterable<TableInfo<Table, dynamic>> allTables,
  Migrator m,
  int from,
  int to,
);
