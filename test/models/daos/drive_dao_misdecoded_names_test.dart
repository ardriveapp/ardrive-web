import 'dart:convert';

import 'package:ardrive/models/models.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:drift/drift.dart';
import 'package:test/test.dart';

import '../../test_utils/utils.dart';

/// Names a misread snapshot damaged before the fix, repaired where they are
/// stored - without a re-sync, and without touching a name that was fine.
void main() {
  late Database db;
  late DriveDao driveDao;

  setUp(() {
    db = getTestDb();
    driveDao = db.driveDao;
  });

  tearDown(() async => db.close());

  String damaged(String name) => String.fromCharCodes(utf8.encode(name));

  Future<void> drive(String id, String name) =>
      db.into(db.drives).insert(DrivesCompanion.insert(
            id: id,
            rootFolderId: '$id-root',
            ownerAddress: 'owner',
            name: name,
            privacy: DrivePrivacyTag.public,
          ));

  Future<void> folder(String id, String name) =>
      db.into(db.folderEntries).insert(FolderEntriesCompanion.insert(
            id: id,
            driveId: 'drive',
            name: name,
            path: '',
          ));

  Future<void> file(String id, String name) =>
      db.into(db.fileEntries).insert(FileEntriesCompanion.insert(
            id: id,
            driveId: 'drive',
            parentFolderId: 'drive-root',
            name: name,
            dataTxId: '$id-tx',
            size: 1,
            lastModifiedDate: DateTime(2024),
            path: '',
          ));

  Future<String> folderName(String id) async =>
      (await (db.select(db.folderEntries)..where((f) => f.id.equals(id)))
              .getSingle())
          .name;

  Future<String> fileName(String id) async =>
      (await (db.select(db.fileEntries)..where((f) => f.id.equals(id)))
              .getSingle())
          .name;

  test('repairs damaged names, and only those', () async {
    await drive('drive', damaged('Public — Archive'));
    await folder('dashes', damaged('Talks — 2024'));
    await folder('japanese', damaged('日本の写真'));
    await folder('fine-accent', 'Café');
    await folder('fine-dash', 'Already — fine');
    await folder('ascii', 'Plain');
    await file('emoji', damaged('Trip 🏔️.jpg'));

    final repaired = await driveDao.repairMisdecodedNames();

    expect(repaired, 4);
    expect(
      (await driveDao.driveById(driveId: 'drive').getSingle()).name,
      'Public — Archive',
    );
    expect(await folderName('dashes'), 'Talks — 2024');
    expect(await folderName('japanese'), '日本の写真');
    expect(await fileName('emoji'), 'Trip 🏔️.jpg');

    // Names that were never damaged.
    expect(await folderName('fine-accent'), 'Café');
    expect(await folderName('fine-dash'), 'Already — fine');
    expect(await folderName('ascii'), 'Plain');
  });

  test('a second run changes nothing', () async {
    await folder('dashes', damaged('Talks — 2024'));

    expect(await driveDao.repairMisdecodedNames(), 1);
    expect(await driveDao.repairMisdecodedNames(), 0);
    expect(await folderName('dashes'), 'Talks — 2024');
  });

  test('repairs the revisions the breadcrumbs read, too', () async {
    await db.into(db.networkTransactions).insert(
          NetworkTransactionsCompanion.insert(id: 'meta'),
        );
    await db.into(db.folderRevisions).insert(FolderRevisionsCompanion.insert(
          folderId: 'f',
          driveId: 'drive',
          name: damaged('Talks — 2024'),
          metadataTxId: 'meta',
          action: 'create',
          dateCreated: Value(DateTime(2024)),
        ));

    await driveDao.repairMisdecodedNames();

    final revision = await (db.select(db.folderRevisions)
          ..where((r) => r.folderId.equals('f')))
        .getSingle();
    expect(revision.name, 'Talks — 2024');
  });
}
