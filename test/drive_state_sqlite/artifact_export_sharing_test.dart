@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:ardrive/drive_state_sqlite/drive_state_artifact_export.dart';
import 'package:ardrive/models/models.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'artifact_fixture.dart';

/// The export shares the app's one connection with everything else: other
/// exports, and sync.
void main() {
  late Directory dir;
  late Database db;
  var sinks = 0;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('artifact-sharing');
    db = Database(NativeDatabase.memory());
    await seedDrive(db, files: 400, folders: 20);
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<DriveStateArtifact> export({bool Function()? isCancelled}) =>
      exportDriveState(
        db,
        driveId: testDriveId,
        producer: 'ArDrive-App/test',
        sink: FileArtifactSink('${dir.path}/artifact_${sinks++}.db'),
        blockEnd: 1814228,
        isCancelled: isCancelled,
      );

  Future<List<String>> attached() async => [
        for (final row in await db.customSelect('PRAGMA database_list').get())
          row.read<String>('name'),
      ];

  test('a second export started during the first waits for it', () async {
    // A snapshot modal closed mid-export left its export running, and the
    // next one collided with it: "database artifact is already in use".
    final results = await Future.wait([export(), export()]);

    expect(results[0].entityCount, greaterThan(400));
    expect(results[1].entityCount, results[0].entityCount);
    expect(await attached(), isNot(contains('artifact')));
  });

  test('a cancelled export is refused and leaves nothing attached', () async {
    await expectLater(
      export(isCancelled: () => true),
      throwsA(isA<ArtifactExportRefused>().having(
        (e) => e.reason,
        'reason',
        ArtifactExportRefusal.cancelled,
      )),
    );

    expect(await attached(), isNot(contains('artifact')));
    expect((await export()).entityCount, greaterThan(400));
  });

  test('a cancel while the export copies stops it before the next table',
      () async {
    var asked = 0;

    await expectLater(
      // Cancelled on the second check: the first table is already copied.
      export(isCancelled: () => ++asked > 2),
      throwsA(isA<ArtifactExportRefused>()),
    );

    expect(await attached(), isNot(contains('artifact')));
  });

  test('an artifact left attached by a failed run does not block the next',
      () async {
    await db.customStatement(
      'ATTACH DATABASE ? AS artifact',
      ['${dir.path}/left_behind.db'],
    );

    expect((await export()).entityCount, greaterThan(400));
    expect(await attached(), isNot(contains('artifact')));
  });

  test('a write made during a refused export is kept', () async {
    // The export refuses because a change to the drive is still pending.
    // With a raw BEGIN, its ROLLBACK also undid whatever the rest of the app
    // had written on the connection in the meantime, such as a sync batch.
    final pendingId = (await db
            .customSelect('SELECT metadataTxId FROM file_revisions LIMIT 1')
            .getSingle())
        .read<String>('metadataTxId');
    await db.customStatement(
      'INSERT INTO network_transactions (id, status) VALUES (?, ?)',
      [pendingId, 'pending'],
    );

    // Written while the export's transaction is open: the export asks
    // whether it is cancelled between tables, and the first table is copied
    // by then.
    Future<void>? writing;
    var asked = 0;
    final exporting = export(isCancelled: () {
      if (++asked == 3) {
        // From outside the export's zone, as a sync batch is. Inside it,
        // Drift would route the write into the export's own transaction.
        writing = Zone.root.run(() => db.customStatement(
              "UPDATE drives SET name = 'renamed by sync' WHERE id = ?",
              [testDriveId],
            ));
      }
      return false;
    });

    await expectLater(
      exporting,
      throwsA(isA<ArtifactExportRefused>().having(
        (e) => e.reason,
        'reason',
        ArtifactExportRefusal.unconfirmedChanges,
      )),
    );
    expect(writing, isNotNull);
    await writing;

    final name = (await db.customSelect('SELECT name FROM drives WHERE id = ?',
            variables: [const Variable<String>(testDriveId)]).getSingle())
        .read<String>('name');
    expect(name, 'renamed by sync');
    expect(await attached(), isNot(contains('artifact')));
  });
}
