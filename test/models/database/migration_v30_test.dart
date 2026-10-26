import 'dart:io';

import 'package:ardrive/models/models.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

/// Schema 30 adds `drives.importedArtifactTxId`. Every existing user opens the
/// app on a version 29 database, so the upgrade is the path that runs.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('migration_v30'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('a version 29 database gains the column and keeps its drives', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final file = File('${dir.path}/db.sqlite');

    // Build version 29 the only way available: create 30, then take the
    // column back out and wind the version back.
    final created = Database(NativeDatabase(file));
    await created.into(created.drives).insert(
          DrivesCompanion.insert(
            id: 'drive-id',
            rootFolderId: 'root-folder-id',
            ownerAddress: 'owner-address',
            name: 'a drive',
            privacy: 'private',
            lastBlockHeight: const Value(1234),
          ),
        );
    await created
        .customStatement('ALTER TABLE drives DROP COLUMN importedArtifactTxId');
    await created.customStatement('PRAGMA user_version = 29');
    await created.close();

    final upgraded = Database(NativeDatabase(file));
    addTearDown(upgraded.close);
    final drive = await upgraded.select(upgraded.drives).getSingle();

    expect(drive.id, 'drive-id');
    expect(drive.lastBlockHeight, 1234);
    expect(drive.importedArtifactTxId, equals(null));
    expect(
      (await upgraded.customSelect('PRAGMA user_version').getSingle())
          .data
          .values
          .single,
      // It carries on to the current version.
      upgraded.schemaVersion,
    );
  });
}
