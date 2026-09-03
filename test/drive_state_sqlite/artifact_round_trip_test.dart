@TestOn('vm')
library;

import 'dart:io';

import 'package:ardrive/drive_state_sqlite/drive_state_artifact_export.dart';
import 'package:ardrive/drive_state_sqlite/drive_state_artifact_import.dart';
import 'package:ardrive/drive_state_sqlite/drive_state_artifact_schema.dart';
import 'package:ardrive/models/models.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:test/test.dart';

import 'artifact_fixture.dart';

void main() {
  late Directory dir;
  late Database producer;
  late Database consumer;

  String p(String name) => '${dir.path}/$name';

  setUp(() {
    dir = Directory.systemTemp.createTempSync('artifact');
    producer = Database(NativeDatabase.memory());
    consumer = Database(NativeDatabase.memory());
  });

  tearDown(() async {
    await producer.close();
    await consumer.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<DriveStateArtifact> export({int files = 200, int? maxBytes}) =>
      exportDriveState(
        producer,
        driveId: testDriveId,
        sink: FileArtifactSink(p('artifact.db')),
        blockEnd: 1814228,
        maxBytes: maxBytes,
      );

  Future<ArtifactImportResult> import(
    DriveStateArtifact artifact, {
    int syncedToBlock = 0,
    String owner = testOwner,
    String privacy = 'private',
  }) async =>
      importDriveState(
        consumer,
        driveId: testDriveId,
        source: await FileArtifactSource.of(p('received.db'), artifact.bytes),
        knownOwner: owner,
        knownPrivacy: privacy,
        syncedToBlock: syncedToBlock,
      );

  group('round trip through a real Drift database', () {
    test('every row arrives, and network_transactions is rebuilt', () async {
      await seedDrive(producer, files: 200, folders: 20);
      final artifact = await export();

      // 200 files + 20 folders + 1 drive.
      expect(artifact.entityCount, 221);
      expect(
        String.fromCharCodes(artifact.bytes.sublist(0, 15)),
        'SQLite format 3',
      );

      final result = await import(artifact);

      expect(result.rowsByTable['file_entries'], 200);
      expect(result.rowsByTable['folder_entries'], 20);
      expect(result.rowsByTable['file_revisions'], 200);
      expect(result.rowsByTable['folder_revisions'], 20);
      expect(result.rowsByTable['drive_revisions'], 1);
      expect(result.rowsByTable['drives'], 1);

      // 200 metadata + 200 data + 20 folder metadata + 1 drive metadata.
      expect(result.transactionsRegenerated, 421);

      final files = await consumer
          .customSelect('SELECT count(*) AS c FROM file_entries')
          .getSingle();
      expect(files.read<int>('c'), 200);
    });

    test('the explorer query returns files — the D2 regression, guarded',
        () async {
      // An artifact carrying entries but no revisions imports 200 files and
      // shows zero of them, because this query INNER JOINs
      // network_transactions through file_revisions. It is the reason the
      // revisions and the regenerated transactions both have to travel.
      await seedDrive(producer, files: 50, folders: 5);
      await import(await export());

      final visible = await consumer.customSelect(
        'SELECT count(*) AS c FROM file_entries f '
        'INNER JOIN file_revisions r ON r.fileId = f.id AND r.driveId = f.driveId '
        'INNER JOIN network_transactions mt ON mt.id = r.metadataTxId '
        'INNER JOIN network_transactions dt ON dt.id = r.dataTxId '
        'WHERE f.driveId = ?',
        variables: [const Variable<String>(testDriveId)],
      ).getSingle();

      expect(visible.read<int>('c'), greaterThan(0),
          reason: 'the drive would render an empty file list');
    });

    test('a second drive in the same database does not travel', () async {
      await seedDrive(producer, files: 20, folders: 2);
      await seedDrive(producer,
          files: 20, folders: 2, driveId: 'other-drive-id');

      final result = await import(await export());
      expect(result.rowsByTable['file_entries'], 20);

      final other = await consumer
          .customSelect('SELECT count(*) AS c FROM file_entries '
              "WHERE driveId = 'other-drive-id'")
          .getSingle();
      expect(other.read<int>('c'), 0);
    });
  });

  group('key material', () {
    test('no wallet, drive key, or sync cursor reaches the artifact',
        () async {
      await seedDrive(producer, files: 50, folders: 5);
      final artifact = await export();

      expect(bytesContain(artifact.bytes, plantedSecret), isFalse,
          reason: 'profiles.encryptedWallet reached the artifact');
      expect(bytesContain(artifact.bytes, 'profiles'), isFalse,
          reason: 'the artifact mentions profiles at all');
      expect(bytesContain(artifact.bytes, 'CURSOR-SECRET'), isFalse,
          reason: 'the local sync cursor travelled');
      for (final column in withheldDriveColumns) {
        expect(bytesContain(artifact.bytes, column), isFalse,
            reason: '"$column" appears in the artifact');
      }
    });

    test('the projection is checked against the live schema', () async {
      // The realistic failure is not this design being wrong today; it is a
      // later migration adding a sensitive column to `drives` that a `SELECT *`
      // would pick up. There is no `SELECT *` here — but this fails the build
      // if a new column appears that nobody classified.
      final columns = await producer
          .customSelect('SELECT name FROM pragma_table_info(?)',
              variables: [const Variable<String>('drives')])
          .get();
      final live = columns.map((r) => r.read<String>('name')).toSet();
      final classified = {
        ...artifactProjection['drives']!,
        ...withheldDriveColumns,
      };

      expect(
        live.difference(classified),
        isEmpty,
        reason: 'drives grew a column that is neither exported nor withheld. '
            'Add it to artifactProjection or to withheldDriveColumns, '
            'deliberately.',
      );
    });
  });

  group('the reader refuses', () {
    late DriveStateArtifact good;

    setUp(() async {
      await seedDrive(producer, files: 30, folders: 3);
      good = await export();
    });

    Future<DriveStateArtifact> tamper(String sql) async {
      final path = p('tampered.db');
      await File(path).writeAsBytes(good.bytes);
      // Raw sqlite3, never Drift: opening an artifact through Database()
      // runs onCreate and writes the app's entire schema into the file.
      final db = raw.sqlite3.open(path);
      db.execute(sql);
      db.dispose();
      return DriveStateArtifact(
        bytes: await File(path).readAsBytes(),
        entityCount: good.entityCount,
        blockEnd: good.blockEnd,
        driveId: good.driveId,
      );
    }

    Future<void> expectRefused(
      DriveStateArtifact artifact,
      ArtifactImportRefusal reason, {
      int syncedToBlock = 0,
      String owner = testOwner,
      String privacy = 'private',
    }) async {
      await expectLater(
        import(artifact,
            syncedToBlock: syncedToBlock, owner: owner, privacy: privacy),
        throwsA(isA<ArtifactImportRefused>()
            .having((e) => e.reason, 'reason', reason)),
      );
      // Nothing was written before the refusal.
      final rows = await consumer
          .customSelect('SELECT count(*) AS c FROM file_entries')
          .getSingle();
      expect(rows.read<int>('c'), 0);
    }

    test('a view', () async {
      await expectRefused(
        await tamper('CREATE VIEW v AS SELECT * FROM file_entries'),
        ArtifactImportRefusal.unexpectedSchema,
      );
    });

    test('a trigger', () async {
      await expectRefused(
        await tamper('CREATE TRIGGER t AFTER INSERT ON meta '
            'BEGIN DELETE FROM file_entries; END'),
        ArtifactImportRefusal.unexpectedSchema,
      );
    });

    test('an extra table', () async {
      await expectRefused(
        await tamper('CREATE TABLE extra (x TEXT)'),
        ArtifactImportRefusal.unexpectedSchema,
      );
    });

    test('an entity count that disagrees with the body', () async {
      await expectRefused(
        await tamper('UPDATE meta SET entityCount = 9999'),
        ArtifactImportRefusal.entityCountMismatch,
      );
    });

    test('an owner who is not the drive owner', () async {
      await expectRefused(good, ArtifactImportRefusal.ownerMismatch,
          owner: 'someone-else');
    });

    test('a privacy that contradicts the local drive', () async {
      await expectRefused(good, ArtifactImportRefusal.privacyMismatch,
          privacy: 'public');
    });

    test('a major version this reader does not implement', () async {
      await expectRefused(
        await tamper("UPDATE meta SET version = '2.0'"),
        ArtifactImportRefusal.unsupportedVersion,
      );
    });

    test('a different 0.x minor — while experimenting, minor is breaking',
        () async {
      // 0.1 and 0.9 share a major. Above 1.0 that would mean "readable"; in
      // the 0.x range it must not, or an artifact published from a staging
      // build could be read by a later build that changed the format
      // underneath it.
      await expectRefused(
        await tamper("UPDATE meta SET version = '0.9'"),
        ArtifactImportRefusal.unsupportedVersion,
      );
    });

    test('a malformed version string', () async {
      await expectRefused(
        await tamper("UPDATE meta SET version = 'banana'"),
        ArtifactImportRefusal.unsupportedVersion,
      );
    });

    test('a range already covered — no rollback', () async {
      await expectRefused(good, ArtifactImportRefusal.rangeAlreadyCovered,
          syncedToBlock: 1814228);
    });

    test('a drive id that is not the one being synced', () async {
      await expectRefused(
        await tamper("UPDATE meta SET driveId = 'other-drive'"),
        ArtifactImportRefusal.driveIdMismatch,
      );
    });
  });

  group('the producer refuses', () {
    test('a drive it does not have', () async {
      await expectLater(
        exportDriveState(producer,
            driveId: 'missing',
            sink: FileArtifactSink(p('a.db')),
            blockEnd: 1),
        throwsA(isA<ArtifactExportRefused>().having(
            (e) => e.reason, 'reason', ArtifactExportRefusal.noSuchDrive)),
      );
    });

    test('an artifact past the producer bound, with a reason', () async {
      await seedDrive(producer, files: 200, folders: 20);
      await expectLater(
        export(maxBytes: 1024),
        throwsA(isA<ArtifactExportRefused>()
            .having((e) => e.reason, 'reason', ArtifactExportRefusal.tooLarge)),
      );
    });
  });
}
