import 'package:ardrive/arns/data/arns_dao.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:drift/drift.dart';

import 'unsupported.dart'
    if (dart.library.html) 'web.dart'
    if (dart.library.io) 'ffi.dart';

part 'database.g.dart';

@DriftDatabase(
  include: {
    '../tables/all.drift',
    '../tables/drive_revisions.drift',
    '../tables/drives.drift',
    '../tables/file_entries.drift',
    '../tables/file_revisions.drift',
    '../tables/folder_entries.drift',
    '../tables/folder_revisions.drift',
    '../tables/licenses.drift',
    '../tables/network_transactions.drift',
    '../tables/profiles.drift',
    '../tables/forgotten_drives.drift',
    '../tables/arns_records.drift',
    '../tables/ant_records.drift',
  },
  daos: [DriveDao, ProfileDao, ARNSDao],
)
class Database extends _$Database {
  Database([QueryExecutor? e]) : super(e ?? openConnection());

  /// Deletes the copies of the database that older builds left in this
  /// browser. Web only, and only from the tab that owns the database; see
  /// `deleteLegacyLocalStores` in web.dart. Returns what it deleted.
  static Future<List<String>> deleteLegacyStores() => deleteLegacyLocalStores();

  /// Whether this tab owns the database (web), or always (elsewhere).
  static bool get ownsDatabase => webDatabaseIsWriter;

  /// A publication's database: in memory, kept nowhere (`PublicationMode`).
  Database.forPublication() : this(openPublicationConnection());

  /// Opens the database, running any migration, and returns why it failed,
  /// or null once it is open.
  Future<Object?> openFailure() async {
    try {
      await customSelect('SELECT 1').get();
      return null;
    } catch (e) {
      return e;
    }
  }

  @override
  int get schemaVersion => 32;
  @override
  MigrationStrategy get migration => MigrationStrategy(
        // Both run in one transaction, which also stamps the new version, so
        // a start cut short (a reload, a closed tab) leaves the database as it
        // was rather than half migrated: drift itself runs each statement on
        // its own and writes `user_version` only after the callback returns.
        onCreate: (Migrator m) => transaction(() async {
          logger.d('Creating database schema...');
          await _clearUnfinishedSchema();
          await m.createAll();
          await _stampSchemaVersion();
        }),
        onUpgrade: (Migrator m, int from, int to) => transaction(() async {
          try {
            logger.d('Migrating schemas from $from thru $to');

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

                await _addColumn(
                  m,
                  driveRevisions,
                  driveRevisions.customJsonMetadata,
                );
                await _addColumn(
                    m, driveRevisions, driveRevisions.customGQLTags);
                await _addColumn(m, drives, drives.customJsonMetadata);
                await _addColumn(m, drives, drives.customGQLTags);

                await _addColumn(
                  m,
                  folderRevisions,
                  folderRevisions.customJsonMetadata,
                );
                await _addColumn(
                    m, folderRevisions, folderRevisions.customGQLTags);
                await _addColumn(
                    m, folderEntries, folderEntries.customJsonMetadata);
                await _addColumn(m, folderEntries, folderEntries.customGQLTags);

                await _addColumn(
                    m, fileRevisions, fileRevisions.customJsonMetadata);
                await _addColumn(m, fileRevisions, fileRevisions.customGQLTags);
                await _addColumn(
                    m, fileEntries, fileEntries.customJsonMetadata);
                await _addColumn(m, fileEntries, fileEntries.customGQLTags);

                await _addColumn(
                    m, fileEntries, fileEntries.pinnedDataOwnerAddress);
                await _addColumn(
                  m,
                  fileRevisions,
                  fileRevisions.pinnedDataOwnerAddress,
                );
              }

              if (from < 18) {
                // Then we're adding the isHidden column
                logger.i('Migrating schema from v17 to v18');

                await _addColumn(m, folderRevisions, folderRevisions.isHidden);
                await _addColumn(m, fileRevisions, fileRevisions.isHidden);

                await _addColumn(m, folderEntries, folderEntries.isHidden);
                await _addColumn(m, fileEntries, fileEntries.isHidden);
              }

              if (from < 19) {
                // Adding licenses
                logger.d('Migrating schema from v18 to v19');

                await m.createTable(licenses);

                await _addColumn(m, fileEntries, fileEntries.licenseTxId);
                await _addColumn(m, fileRevisions, fileRevisions.licenseTxId);
              }

              if (from < 20) {
                // Adding snapshot entries
                logger.d('Migrating schema from v19 to v20');

                await _addColumn(m, fileEntries, fileEntries.thumbnail);
                await _addColumn(m, fileRevisions, fileRevisions.thumbnail);
              }
            }

            if (from < 21) {
              // Adding assigned names
              logger.d('Migrating schema from v20 to v21');

              await _addColumn(m, fileRevisions, fileRevisions.assignedNames);
              await _addColumn(m, fileEntries, fileEntries.assignedNames);

              await m.createTable(arnsRecords);
              await m.createTable(antRecords);
            }

            if (from < 22) {
              logger.d('Migrating schema from v21 to v22');

              logger.d('Dropping snapshot_entries table');

              await customStatement('''
                  DROP TABLE IF EXISTS snapshot_entries;
              ''');

              logger.d('snapshot_entries table dropped');
            }
            if (from < 23) {
              logger.d('Migrating schema from v22 to v23');

              await _addColumn(m, drives, drives.isHidden);
              await _addColumn(m, driveRevisions, driveRevisions.isHidden);
            }
            if (from < 24) {
              logger.d('Migrating schema from v23 to v24');

              await _addColumn(m, fileEntries, fileEntries.fallbackTxId);
              await _addColumn(m, fileRevisions, fileRevisions.fallbackTxId);
            }
            if (from < 25) {
              logger.d('Migrating schema from v24 to v25');
              logger.d('Adding search optimization indexes');

              // Create indexes for search optimization
              await customStatement('''
                CREATE INDEX IF NOT EXISTS idx_drives_name ON drives(name);
                CREATE INDEX IF NOT EXISTS idx_file_entries_name ON file_entries(name);
                CREATE INDEX IF NOT EXISTS idx_folder_entries_name ON folder_entries(name);
              ''');

              logger.d('Search optimization indexes created');
            }
            if (from < 26) {
              logger.d('Migrating schema from v25 to v26');

              await _addColumn(m, fileEntries, fileEntries.originalOwner);
              await _addColumn(m, fileRevisions, fileRevisions.originalOwner);

              await _addColumn(m, fileEntries, fileEntries.importSource);
              await _addColumn(m, fileRevisions, fileRevisions.importSource);
            }

            if (from < 27) {
              logger.d('Migrating schema from v26 to v27');

              await _addColumn(m, drives, drives.signatureType);
              await _addColumn(m, drives, drives.driveKeyGenerated);
            }

            if (from < 28) {
              logger.d('Migrating schema from v27 to v28');

              await _addColumn(m, profiles, profiles.sourceWalletAddress);
            }

            if (from < 29) {
              logger.d('Migrating schema from v28 to v29');
              logger.d('Adding sync performance indexes');
              await customStatement('''
                CREATE INDEX IF NOT EXISTS idx_file_revisions_data_tx_id ON file_revisions(dataTxId);
              ''');
              await customStatement('''
                CREATE INDEX IF NOT EXISTS idx_network_transactions_status ON network_transactions(status);
              ''');
              logger.d('Sync performance indexes created');
            }

            if (from < 30) {
              logger.d('Migrating schema from v29 to v30');

              await _addColumn(m, drives, drives.importedArtifactTxId);
            }

            if (from < 31) {
              logger.d('Migrating schema from v30 to v31');

              // A cache of ArNS with nothing reading it until now: rebuilt in
              // its new shape rather than migrated.
              await m.deleteTable('arns_records');
              await m.deleteTable('ant_records');
              await m.createTable(arnsRecords);
              await m.createTable(antRecords);
            }

            if (from < 32) {
              logger.d('Migrating schema from v31 to v32');

              // The 3.0 local profile format (ProfileDao): the columns only.
              // Each profile is rewritten in the new format on its next
              // unlock, when the password that opens it is at hand.
              await _addColumn(m, profiles, profiles.formatVersion);
              await _addColumn(m, profiles, profiles.deviceSalt);
              await _addColumn(m, profiles, profiles.unlockMethod);
              await _addColumn(m, profiles, profiles.keyCheck);
              await customStatement(
                'CREATE TABLE IF NOT EXISTS forgotten_drives '
                '(driveId TEXT NOT NULL PRIMARY KEY)',
              );
            }

            await _stampSchemaVersion();
          } catch (e, stacktrace) {
            logger.e(
              'CRITICAL! Failed to migrate database from $from to $to',
              e,
              stacktrace,
            );
            rethrow;
          }
        }),
        beforeOpen: (_) => enableSecureDelete(),
      );

  /// Deleted rows are overwritten with zeros rather than left in free pages
  /// of the file. The profile (the stored wallet) and the drive keys are
  /// encrypted, but a copy of the file taken after sign-out could still be
  /// attacked offline through the password. Per connection, so it runs on
  /// every open. docs/WEB_DATABASE.md, "Signing out".
  Future<void> enableSecureDelete() =>
      customStatement('PRAGMA secure_delete = ON');

  /// Rebuilds the file without its free pages: what was deleted before
  /// [enableSecureDelete] existed is in them. Sign-out runs it once the
  /// tables are empty, when it is quick. Never inside a transaction.
  Future<void> vacuum() => customStatement('VACUUM');

  /// Adds [column] to [table] unless it is already there.
  ///
  /// Builds before the transaction above ran each upgrade statement on its
  /// own, so an upgrade cut short could add a column and leave the version
  /// where it was; the step then ran again on every start and failed on the
  /// duplicate. Skipping a column that exists lets those databases finish
  /// their upgrade on their own.
  Future<void> _addColumn(
    Migrator m,
    TableInfo table,
    GeneratedColumn column,
  ) async {
    final quoted = table.actualTableName.replaceAll('"', '""');
    final columns = await customSelect('PRAGMA table_info("$quoted")').get();
    if (columns.any((c) => c.read<String>('name') == column.name)) return;
    await m.addColumn(table, column);
  }

  /// Writes [schemaVersion] inside the migration's transaction, so the schema
  /// and the version that describes it commit together. drift writes it again
  /// once the migration returns, to the same value.
  Future<void> _stampSchemaVersion() =>
      customStatement('PRAGMA user_version = $schemaVersion');

  /// Clears what an earlier build's first start left when it was cut short.
  ///
  /// drift runs `onCreate` whenever `user_version` is 0. Builds before the
  /// transaction above created the schema one statement at a time, so a
  /// reload during the first start kept the tables and indexes made so far
  /// with the version still 0, and every later start failed on the first
  /// `CREATE INDEX` that already existed. Nothing can have been written to
  /// such a database (no query runs until the schema is made), so what is
  /// there goes, and the schema is made again in full, in its current shape.
  ///
  /// A database at version 0 that holds rows is not an unfinished first start,
  /// and is refused rather than cleared.
  Future<void> _clearUnfinishedSchema() async {
    final leftovers = await customSelect(
      "SELECT type, name FROM sqlite_master WHERE name NOT LIKE 'sqlite\\_%' "
      "ESCAPE '\\' AND type IN ('table', 'view', 'trigger')",
    ).get();
    if (leftovers.isEmpty) return;

    final tables = [
      for (final row in leftovers)
        if (row.read<String>('type') == 'table') row.read<String>('name'),
    ];
    for (final table in tables) {
      final quoted = '"${table.replaceAll('"', '""')}"';
      final hasRows = await customSelect(
        'SELECT EXISTS (SELECT 1 FROM $quoted) AS has_rows',
      ).getSingle();
      if (hasRows.read<bool>('has_rows')) {
        throw UnexpectedDatabaseContents(table);
      }
    }

    logger.w('Clearing an unfinished schema: ${leftovers.length} objects');
    // Views and triggers first, then tables, whose indexes go with them.
    for (final type in ['view', 'trigger', 'table']) {
      for (final row in leftovers) {
        if (row.read<String>('type') != type) continue;
        final name = row.read<String>('name').replaceAll('"', '""');
        await customStatement('DROP ${type.toUpperCase()} IF EXISTS "$name"');
      }
    }
  }
}

/// Thrown by `onCreate` for a database at schema version 0 that holds rows:
/// not an unfinished first start, so it is refused rather than cleared.
class UnexpectedDatabaseContents implements Exception {
  UnexpectedDatabaseContents(this.table);

  final String table;

  @override
  String toString() => 'UnexpectedDatabaseContents: the database has no '
      'schema version but $table holds rows; not clearing it';
}
