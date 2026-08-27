@TestOn('vm')
library;

import 'dart:io';

import 'package:ardrive/drive_state_sqlite/drive_state_artifact_export.dart';
import 'package:ardrive/drive_state_sqlite/drive_state_artifact_import.dart';
import 'package:ardrive/models/models.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'artifact_fixture.dart';

/// Folders are the case where "copy the rows" is not obviously sufficient, so
/// each shape a folder can take is round-tripped rather than assumed.
///
/// An empty folder has no files to imply it, a ghost folder has no revision to
/// describe it, and a nested folder means nothing if its parent did not
/// travel. All three are rows in `folder_entries`, which is why they survive —
/// but that is a claim worth executing.
void main() {
  late Directory dir;
  late Database producer;
  late Database consumer;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('folders');
    producer = Database(NativeDatabase.memory());
    consumer = Database(NativeDatabase.memory());
  });

  tearDown(() async {
    await producer.close();
    await consumer.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> roundTrip() async {
    final artifact = await exportDriveState(
      producer,
      driveId: testDriveId,
      sink: FileArtifactSink('${dir.path}/a.db'),
      blockEnd: 1814228,
    );
    await importDriveState(
      consumer,
      driveId: testDriveId,
      source:
          await FileArtifactSource.of('${dir.path}/r.db', artifact.bytes),
      knownOwner: testOwner,
      knownPrivacy: 'private',
      syncedToBlock: 0,
    );
  }

  Future<List<String>> folderIds(Database db) async {
    final rows = await db
        .customSelect('SELECT id FROM folder_entries ORDER BY id')
        .get();
    return rows.map((r) => r.read<String>('id')).toList();
  }

  test('an empty folder survives — nothing else implies it', () async {
    await seedDrive(producer, files: 5, folders: 2);
    // A third folder with no files at all. If folder_entries did not travel,
    // this is precisely the row that would vanish without trace: no file
    // references it, so nothing would rebuild it.
    await producer.customStatement(
      'INSERT INTO folder_entries (id, driveId, name, parentFolderId, path, '
      'dateCreated, lastUpdated, isGhost, isHidden) '
      "VALUES ('empty-folder', ?, 'Empty', ?, '/Empty', "
      '1700000000, 1700000000, 0, 0)',
      [testDriveId, 'root-$testDriveId'],
    );
    await producer.customStatement(
      'INSERT INTO folder_revisions (folderId, driveId, name, parentFolderId, '
      'metadataTxId, dateCreated, action, isHidden) '
      "VALUES ('empty-folder', ?, 'Empty', ?, 'empty-meta-tx', "
      "1700000000, 'create', 0)",
      [testDriveId, 'root-$testDriveId'],
    );

    await roundTrip();

    expect(await folderIds(consumer), contains('empty-folder'));
    final row = await consumer
        .customSelect(
          "SELECT name, path FROM folder_entries WHERE id = 'empty-folder'",
        )
        .getSingle();
    expect(row.read<String>('name'), 'Empty');
    expect(row.read<String>('path'), '/Empty');
  });

  test('a ghost folder survives, and stays a ghost', () async {
    // A ghost is a folder referenced by files whose own metadata was never
    // found — a normal state, not corruption. It has an entry row and no
    // revision, which is exactly the shape an export that only carried
    // revisions would drop while keeping the files inside it. Those files
    // would then be unreachable, because nothing lists a file except by its
    // parent.
    await seedDrive(producer, files: 5, folders: 2);
    await producer.customStatement(
      'INSERT INTO folder_entries (id, driveId, name, parentFolderId, path, '
      'dateCreated, lastUpdated, isGhost, isHidden) '
      "VALUES ('ghost-folder', ?, 'Ghost', ?, '/Ghost', "
      '1700000000, 1700000000, 1, 0)',
      [testDriveId, 'root-$testDriveId'],
    );
    await producer.customStatement(
      'INSERT INTO file_entries (id, driveId, name, parentFolderId, path, '
      'size, lastModifiedDate, dataContentType, dataTxId, isHidden, '
      'dateCreated, lastUpdated) '
      "VALUES ('orphan-file', ?, 'orphan.pdf', 'ghost-folder', "
      "'/Ghost/orphan.pdf', 10, 1700000000, 'application/pdf', "
      "'orphan-data-tx', 0, 1700000000, 1700000000)",
      [testDriveId],
    );

    await roundTrip();

    expect(await folderIds(consumer), contains('ghost-folder'));
    final ghost = await consumer
        .customSelect(
          "SELECT isGhost FROM folder_entries WHERE id = 'ghost-folder'",
        )
        .getSingle();
    expect(ghost.read<int>('isGhost'), 1,
        reason: 'a ghost that arrives as an ordinary folder is a folder the '
            'user can never fix');

    // And the file inside it is reachable, which is the thing the ghost row
    // exists to make possible.
    final child = await consumer
        .customSelect(
          'SELECT count(*) AS c FROM file_entries '
          "WHERE parentFolderId = 'ghost-folder'",
        )
        .getSingle();
    expect(child.read<int>('c'), 1);
  });

  test('folder revisions travel, so the folder has a history', () async {
    await seedDrive(producer, files: 5, folders: 3);
    await roundTrip();

    final revisions = await consumer
        .customSelect('SELECT count(*) AS c FROM folder_revisions')
        .getSingle();
    expect(revisions.read<int>('c'), 3);
  });

  test('every folder in the drive arrives, not only those holding files',
      () async {
    await seedDrive(producer, files: 3, folders: 20);
    await roundTrip();

    // 20 folders, 3 files: at most three folders contain anything.
    expect((await folderIds(consumer)).length, 20);
  });
}
