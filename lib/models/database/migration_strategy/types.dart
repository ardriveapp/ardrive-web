// import 'package:drift/drift.dart';

// class Migration extends MigrationStrategy {
//   Migration({required OnCreate onCreate, required OnUpgrade onUpgrade})
//       : super(onCreate: onCreate, onUpgrade: onUpgrade);
// }

// class CustomMigration {
//   final bool Function(int from, int to) testVersionMatch;
//   final void Function(Migrator m, int from, int to) onUpgrade;

//   static final List<CustomMigration> _instances = [];

//   const CustomMigration._new(this.testVersionMatch, this.onUpgrade);

//   CustomMigration getForVersion(int from, int to) {
//     for (final instance in _instances) {
//       if (instance.testVersionMatch(from, to)) {
//         return instance;
//       }
//     }

//     throw NoMigrationFoundException(from, to);
//   }

//   factory CustomMigration(
//     bool Function(int from, int to) testVersionMatch,
//     void Function(Migrator m, int from, int to) onUpgrade,
//   ) {
//     final newInstance = CustomMigration._new(testVersionMatch, onUpgrade);
//     _instances.add(newInstance);
//     return newInstance;
//   }
// }

// class NoMigrationFoundException implements Exception {
//   final int from;
//   final int to;

//   NoMigrationFoundException(this.from, this.to);

//   @override
//   String toString() =>
//       'NoMigrationFoundException: No migration found for version $from to $to';
// }

import 'package:drift/drift.dart';

typedef CustomOnUpgrade = Future<void> Function(
  Iterable<TableInfo<Table, dynamic>> allTables,
  Migrator m,
  int from,
  int to,
);
