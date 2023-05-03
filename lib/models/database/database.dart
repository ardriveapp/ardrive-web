import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/models/database/migration_strategy/resolve_migration.dart';
import 'package:ardrive/models/database/migration_strategy/types.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

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
  int get schemaVersion => 16;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) {
          logger.i('Creating all tables');
          return m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          CustomOnUpgrade migration = resolveMigration(from, to);
          try {
            await migration(allTables, m, from, to);
          } catch (e, s) {
            logger.i('Database migration failed (v$from -> v$to): $e\n$s');
            // Fallback to default migration
            migration = resolveMigration(
              from,
              to,
              forceFallbackToDefault: true,
            );
            await migration(allTables, m, from, to);
          }
        },
      );
}
