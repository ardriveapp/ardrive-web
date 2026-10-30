import 'dart:io';

import 'package:ardrive/models/models.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:test/test.dart';

import '../../test_utils/schema_statements.dart';

/// A first start or an upgrade cut short, by a reload or a closed tab, must
/// never leave a database the next start cannot open.
///
/// Each start is modelled by an executor that fails at its nth schema
/// statement ([SchemaStatements]). A failure inside a transaction rolls it back, which is where a
/// killed worker's journal leaves the file too; a failure outside one leaves
/// the statements before it in place, which is where a kill leaves them.
/// `web_worker_database_test.dart` kills a real worker instead.
void main() {
  late Directory dir;
  var files = 0;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  setUp(() => dir = Directory.systemTemp.createTempSync('interrupted_schema'));
  tearDown(() => dir.deleteSync(recursive: true));

  File newFile() => File('${dir.path}/db-${files++}.sqlite');

  Future<int> userVersion(Database db) async =>
      (await db.customSelect('PRAGMA user_version').getSingle())
          .data
          .values
          .single as int;

  /// Every table, index, view and trigger, with the SQL that made it.
  Future<Map<String, String?>> schemaOf(Database db) async => {
        for (final row in await db
            .customSelect(
                'SELECT type, name, sql FROM sqlite_master WHERE name '
                "NOT LIKE 'sqlite\\_%' ESCAPE '\\' ORDER BY name")
            .get())
          '${row.read<String>('type')} ${row.read<String>('name')}':
              row.readNullable<String>('sql'),
      };

  late Map<String, String?> cleanSchema;
  late int createStatements;

  setUp(() async {
    final counter = SchemaStatements();
    final clean = Database(NativeDatabase(newFile()).interceptWith(counter));
    cleanSchema = await schemaOf(clean);
    createStatements = counter.count;
    await clean.close();
  });

  Future<void> expectOpensWithFullSchema(File file) async {
    final db = Database(NativeDatabase(file));
    try {
      expect(await schemaOf(db), cleanSchema);
      expect(await userVersion(db), db.schemaVersion);
      await db.into(db.networkTransactions).insert(
          NetworkTransactionsCompanion.insert(id: 'tx'),
          mode: InsertMode.insertOrReplace);
    } finally {
      await db.close();
    }
  }

  group('a first start cut short', () {
    test('at any statement of schema creation, the next start completes it',
        () async {
      expect(createStatements, greaterThan(10));
      for (var n = 1; n <= createStatements; n++) {
        final file = newFile();
        final cut = Database(NativeDatabase(file).interceptWith(_failAt(n)));
        await expectLater(cut.customSelect('SELECT 1').get(), throwsA(anything),
            reason: 'statement $n was to fail');
        await cut.close();

        await expectOpensWithFullSchema(file);
      }
    });

    test('a schema left half made by an earlier build is made again', () async {
      // Earlier builds created the schema one statement at a time, so a cut
      // left the first statements in place and user_version at 0.
      final made = <String>[];
      final reference = Database(NativeDatabase(newFile()));
      for (final entity in reference.allSchemaEntities) {
        final row = await reference.customSelect(
            'SELECT sql FROM sqlite_master WHERE name = ?',
            variables: [Variable(entity.entityName)]).getSingle();
        made.add(row.read<String>('sql'));
      }
      await reference.close();

      for (var n = 1; n <= made.length; n++) {
        final file = newFile();
        final half = raw.sqlite3.open(file.path);
        made.take(n).forEach(half.execute);
        half.dispose();

        await expectOpensWithFullSchema(file);
      }
    });

    test('a leftover table in an older shape is made in the current one',
        () async {
      final file = newFile();
      final half = raw.sqlite3.open(file.path);
      half.execute('CREATE TABLE ant_records (domain TEXT NOT NULL PRIMARY KEY,'
          ' process_id TEXT NOT NULL)');
      half.execute('CREATE INDEX idx_drives_name ON ant_records(domain)');
      half.dispose();

      await expectOpensWithFullSchema(file);
    });

    test('a database at version 0 that holds rows is refused, not cleared',
        () async {
      final file = newFile();
      final held = raw.sqlite3.open(file.path);
      held.execute('CREATE TABLE drives (id TEXT PRIMARY KEY)');
      held.execute("INSERT INTO drives VALUES ('kept')");
      held.dispose();

      final db = Database(NativeDatabase(file));
      await expectLater(db.customSelect('SELECT 1').get(), throwsA(anything));
      await db.close();

      final after = raw.sqlite3.open(file.path);
      expect(after.select('SELECT id FROM drives').single['id'], 'kept');
      after.dispose();
    });
  });

  group('an upgrade cut short', () {
    /// A version 28 database holding a drive: what schema 29 to 31 changed,
    /// taken back out of a fresh one.
    Future<File> version28() async {
      final file = newFile();
      final db = Database(NativeDatabase(file));
      await db.into(db.drives).insert(DrivesCompanion.insert(
            id: 'drive-id',
            rootFolderId: 'root-folder-id',
            ownerAddress: 'owner-address',
            name: 'a drive',
            privacy: 'public',
          ));
      await db.customStatement('DROP INDEX idx_file_revisions_data_tx_id');
      await db.customStatement('DROP INDEX idx_network_transactions_status');
      await db.customStatement(
          'ALTER TABLE drives DROP COLUMN importedArtifactTxId');
      await db.customStatement('DROP TABLE arns_records');
      await db.customStatement('DROP TABLE ant_records');
      await db.customStatement('''
        CREATE TABLE arns_records (
          transaction_id TEXT NOT NULL, file_id TEXT NOT NULL,
          ttl INTEGER NOT NULL, name TEXT NOT NULL, domain TEXT NOT NULL,
          id TEXT NOT NULL PRIMARY KEY, is_active BOOLEAN)''');
      await db.customStatement('''
        CREATE TABLE ant_records (
          domain TEXT NOT NULL PRIMARY KEY, process_id TEXT NOT NULL)''');
      await db.customStatement('PRAGMA user_version = 28');
      await db.close();
      return file;
    }

    test('at any statement, the next start finishes it and keeps the data',
        () async {
      final counter = SchemaStatements();
      final whole =
          Database(NativeDatabase(await version28()).interceptWith(counter));
      await whole.customSelect('SELECT 1').get();
      await whole.close();
      final upgradeStatements = counter.count;
      expect(upgradeStatements, greaterThan(4));

      for (var n = 1; n <= upgradeStatements; n++) {
        final file = await version28();
        final cut = Database(NativeDatabase(file).interceptWith(_failAt(n)));
        await expectLater(cut.customSelect('SELECT 1').get(), throwsA(anything),
            reason: 'statement $n was to fail');
        await cut.close();

        final db = Database(NativeDatabase(file));
        try {
          expect(await userVersion(db), db.schemaVersion,
              reason: 'cut at statement $n');
          final drive = await db.select(db.drives).getSingle();
          expect(drive.id, 'drive-id');
          expect(drive.importedArtifactTxId, isNull);
          final indexes = (await schemaOf(db)).keys.where((k) =>
              k == 'index idx_file_revisions_data_tx_id' ||
              k == 'index idx_network_transactions_status');
          expect(indexes, hasLength(2));
        } finally {
          await db.close();
        }
      }
    });

    test('a version 28 database an earlier build half upgraded finishes it',
        () async {
      // What 2.90 ran, one statement at a time and outside any transaction,
      // to take version 28 to 31: a cut after the column left it in place
      // with the version at 28, and every later start failed on the
      // duplicate column.
      final reference = Database(NativeDatabase(newFile()));
      Future<String> sqlOf(String name) async => (await reference.customSelect(
              'SELECT sql FROM sqlite_master WHERE name = ?',
              variables: [Variable(name)]).getSingle())
          .read<String>('sql');
      final earlierUpgrade = [
        'CREATE INDEX IF NOT EXISTS idx_file_revisions_data_tx_id '
            'ON file_revisions(dataTxId)',
        'CREATE INDEX IF NOT EXISTS idx_network_transactions_status '
            'ON network_transactions(status)',
        'ALTER TABLE drives ADD COLUMN importedArtifactTxId TEXT',
        'DROP TABLE IF EXISTS arns_records',
        'DROP TABLE IF EXISTS ant_records',
        await sqlOf('arns_records'),
        await sqlOf('ant_records'),
      ];
      await reference.close();

      for (var k = 3; k <= earlierUpgrade.length; k++) {
        final file = await version28();
        final half = raw.sqlite3.open(file.path);
        earlierUpgrade.take(k).forEach(half.execute);
        expect(half.userVersion, 28);
        half.dispose();

        final db = Database(NativeDatabase(file));
        try {
          expect(await db.openFailure(), isNull, reason: 'after $k statements');
          expect(await userVersion(db), db.schemaVersion);
          expect((await db.select(db.drives).getSingle()).id, 'drive-id');
          await db.into(db.antRecords).insert(AntRecordsCompanion.insert(
                domain: 'acme',
                processId: 'ant',
                arnsAddress: 'sol',
                role: 'owner',
                nameType: 'lease',
                undernameLimit: 10,
              ));
        } finally {
          await db.close();
        }
      }
    });
  });
}

SchemaStatements _failAt(int n) => SchemaStatements(
      at: n,
      instead: (statement) =>
          Future.error(StateError('cut at statement $n: $statement')),
    );
