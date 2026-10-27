import 'dart:io';

import 'package:ardrive/models/models.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

/// Schema 31 rebuilds `arns_records` and `ant_records` as the ArNS cache
/// (docs/NAMES.md). Nothing read the old shape, so its rows go.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('migration_v31'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('a version 30 database gets the new cache tables and keeps its drives',
      () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final file = File('${dir.path}/db.sqlite');

    // Build version 30: create the current schema, then put the old ArNS
    // tables back with a row each and wind the version back.
    final created = Database(NativeDatabase(file));
    await created.into(created.drives).insert(
          DrivesCompanion.insert(
            id: 'drive-id',
            rootFolderId: 'root-folder-id',
            ownerAddress: 'owner-address',
            name: 'a drive',
            privacy: 'public',
          ),
        );
    await created.customStatement('DROP TABLE arns_records');
    await created.customStatement('DROP TABLE ant_records');
    await created.customStatement('''
      CREATE TABLE arns_records (
        transaction_id TEXT NOT NULL, file_id TEXT NOT NULL,
        ttl INTEGER NOT NULL, name TEXT NOT NULL, domain TEXT NOT NULL,
        id TEXT NOT NULL PRIMARY KEY, is_active BOOLEAN)''');
    await created.customStatement('''
      CREATE TABLE ant_records (
        domain TEXT NOT NULL PRIMARY KEY, process_id TEXT NOT NULL)''');
    await created.customStatement(
        "INSERT INTO arns_records VALUES ('tx', 'file', 900, '@', 'acme', 'id', 1)");
    await created
        .customStatement("INSERT INTO ant_records VALUES ('acme', 'ant')");
    await created.customStatement('PRAGMA user_version = 30');
    await created.close();

    final upgraded = Database(NativeDatabase(file));
    addTearDown(upgraded.close);

    expect((await upgraded.select(upgraded.drives).getSingle()).id, 'drive-id');
    expect(await upgraded.select(upgraded.arnsRecords).get(), isEmpty);
    expect(await upgraded.select(upgraded.antRecords).get(), isEmpty);

    await upgraded.into(upgraded.antRecords).insert(
          AntRecordsCompanion.insert(
            domain: 'acme',
            processId: 'ant',
            arnsAddress: 'sol',
            role: 'owner',
            nameType: 'lease',
            endTimestamp: const Value(1800000000000),
            undernameLimit: 10,
          ),
        );
    expect(
      (await upgraded.select(upgraded.antRecords).getSingle()).undernameLimit,
      10,
    );
    expect(
      (await upgraded.customSelect('PRAGMA user_version').getSingle())
          .data
          .values
          .single,
      31,
    );
  });
}
