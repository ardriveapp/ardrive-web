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
int _rss() => ProcessInfo.currentRss ~/ 1048576;

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

    final rssBefore = _rss();
    final seeded = DateTime.now();
    await seedDrive(producer, files: files, folders: folders);
    final seedMs = DateTime.now().difference(seeded).inMilliseconds;

    final afterSeed = _rss();
    final built = DateTime.now();
    final artifact = await exportDriveState(
      producer,
      driveId: testDriveId,
      sink: FileArtifactSink('${dir.path}/artifact.db'),
      blockEnd: 1814228,
    );
    final buildMs = DateTime.now().difference(built).inMilliseconds;

    final gzipStarted = DateTime.now();
    final gzipped = gzip.encode(artifact.bytes).length;
    final gzipMs = DateTime.now().difference(gzipStarted).inMilliseconds;
    final afterSeal = _rss();

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
    final afterImport = _rss();

    // ignore: avoid_print
    print('''

  SQLite artifact, $files files / $folders folders
  ------------------------------------------------------
  seeded in                 $seedMs ms
  artifact (uncompressed)   ${artifact.bytes.length} B = ${(artifact.bytes.length / 1048576).toStringAsFixed(2)} MiB
  artifact (gzipped)        $gzipped B = ${(gzipped / 1048576).toStringAsFixed(2)} MiB
  compression ratio         ${(artifact.bytes.length / gzipped).toStringAsFixed(2)}x
  bytes per entity (uncomp) ${artifact.bytes.length ~/ artifact.entityCount}
  entities                  ${artifact.entityCount}
  rows merged               ${result.totalRows}
  network_transactions      ${result.transactionsRegenerated}

  export (ATTACH+INSERT)    $buildMs ms
  gzip                      $gzipMs ms
  producer, end to end      ${buildMs + gzipMs} ms
  import, end to end        $importMs ms

  RSS - a VM figure, not a browser heap; process-wide
  before seeding            $rssBefore MiB
  after seeding             $afterSeed MiB
  after export              ${_rss()} MiB
  after gzip                $afterSeal MiB
  after import              $afterImport MiB

  #2188 (JSON), the same test run on this machine:
  serialised 52.16 MiB / gzipped 9.55 MiB / ratio 5.46x / 1306 B per entity
  export 9111 ms + jsonEncode 1274 ms + gzip 2619 ms = 13004 ms producer
  import 7444 ms end to end
  RSS 787 MiB before seeding, run peak 1003 MiB
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
