@TestOn('vm')
library;

import 'dart:io';

import 'package:ardrive/drive_state_sqlite/drive_state_artifact_export.dart';
import 'package:ardrive/drive_state_sqlite/drive_state_artifact_import.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'artifact_fixture.dart';

/// The head-to-head against D1's JSON path.
///
/// `#2188` measured its own exporter at 41,767 files: **52.16 MiB serialised,
/// 9.55 MiB gzipped, 4 s to seal, 9 s to import**, with the producer peaking
/// near 950 MiB from a 263 MiB baseline. This builds the same drive through
/// the SQLite path and weighs the same things, so the two numbers are about
/// the same work rather than about two different fixtures.
///
/// Skipped by default — it costs a minute and asserts almost nothing. Run it
/// with:
///
/// ```
/// flutter test test/drive_state_sqlite/artifact_scale_test.dart --run-skipped
/// ```
void main() {
  test('41,767 files through the SQLite path', () async {
    const files = 41767;
    const folders = 430;

    final dir = Directory.systemTemp.createTempSync('artifact_scale');
    addTearDown(() => dir.deleteSync(recursive: true));

    final producer = Database(NativeDatabase.memory());
    final consumer = Database(NativeDatabase.memory());
    addTearDown(producer.close);
    addTearDown(consumer.close);

    final seeded = DateTime.now();
    await seedDrive(producer, files: files, folders: folders);
    final seedMs = DateTime.now().difference(seeded).inMilliseconds;

    final built = DateTime.now();
    final artifact = await exportDriveState(
      producer,
      driveId: testDriveId,
      sink: FileArtifactSink('${dir.path}/artifact.db'),
      blockEnd: 1814228,
    );
    final buildMs = DateTime.now().difference(built).inMilliseconds;

    final gzipped = gzip.encode(artifact.bytes).length;

    final imported = DateTime.now();
    final result = await importDriveState(
      consumer,
      driveId: testDriveId,
      source: await FileArtifactSource.of(
          '${dir.path}/received.db', artifact.bytes),
      knownOwner: testOwner,
      knownPrivacy: 'private',
      syncedToBlock: 0,
    );
    final importMs = DateTime.now().difference(imported).inMilliseconds;

    // ignore: avoid_print
    print('''

  SQLite artifact, $files files / $folders folders
  ------------------------------------------------------
  seeded in                 $seedMs ms
  artifact (uncompressed)   ${artifact.bytes.length} B
                            ${(artifact.bytes.length / 1048576).toStringAsFixed(2)} MiB
  artifact (gzipped)        $gzipped B
                            ${(gzipped / 1048576).toStringAsFixed(2)} MiB
  entities                  ${artifact.entityCount}
  rows merged               ${result.totalRows}
  network_transactions      ${result.transactionsRegenerated}
  build                     $buildMs ms
  import                    $importMs ms

  #2188 (JSON) for comparison, at the same file count:
  serialised 52.16 MiB / gzipped 9.55 MiB / seal 4000 ms / import 9000 ms
''');

    expect(result.rowsByTable['file_entries'], files);
    expect(artifact.entityCount, files + folders + 1);
  },
      timeout: const Timeout(Duration(minutes: 10)),
      skip: 'A measurement, not an assertion: it builds a drive at production '
          'scale and weighs the result. It is the source of the figures in '
          'docs/drive-state/SQLITE_ARTIFACT.md, so it is kept runnable and '
          'skipped by default. Run it with --run-skipped.');
}
