import 'package:ardrive/models/models.dart';
import 'package:drift/drift.dart';
import 'package:test/test.dart';

import '../../test_utils/utils.dart';

/// The transactions a wallet's drives are made of, which decide what of its
/// AR spending was ArDrive storage.
void main() {
  late Database db;
  late DriveDao driveDao;

  setUp(() {
    db = getTestDb();
    driveDao = db.driveDao;
  });

  tearDown(() async => db.close());

  Future<void> tx(String id) => db.into(db.networkTransactions).insert(
        NetworkTransactionsCompanion.insert(id: id),
        mode: InsertMode.insertOrIgnore,
      );

  Future<void> fileRevision(
    String driveId,
    String fileId, {
    required String metadata,
    required String data,
    String? bundle,
  }) async {
    await tx(metadata);
    await tx(data);
    await db.into(db.fileRevisions).insert(FileRevisionsCompanion.insert(
          fileId: fileId,
          driveId: driveId,
          name: fileId,
          parentFolderId: 'root',
          size: 1,
          lastModifiedDate: DateTime(2024),
          metadataTxId: metadata,
          dataTxId: data,
          action: 'create',
          bundledIn: Value(bundle),
        ));
  }

  test('every file revision, folder and drive transaction, and their bundles',
      () async {
    await fileRevision('mine', 'a', metadata: 'a-meta', data: 'a-data');
    await fileRevision('mine', 'b',
        metadata: 'b-meta', data: 'b-data', bundle: 'bundle-1');

    await tx('folder-meta');
    await db.into(db.folderRevisions).insert(FolderRevisionsCompanion.insert(
          folderId: 'f',
          driveId: 'mine',
          name: 'f',
          metadataTxId: 'folder-meta',
          action: 'create',
        ));

    await tx('drive-meta');
    await db.into(db.driveRevisions).insert(DriveRevisionsCompanion.insert(
          driveId: 'mine',
          rootFolderId: 'root',
          ownerAddress: 'me',
          name: 'mine',
          privacy: 'public',
          metadataTxId: 'drive-meta',
          action: 'create',
          bundledIn: const Value('bundle-2'),
        ));

    const all = {
      'a-meta',
      'a-data',
      'b-meta',
      'b-data',
      'bundle-1',
      'folder-meta',
      'drive-meta',
      'bundle-2',
    };
    expect(
      await driveDao.arDriveTransactionsAmong(['mine'], {...all, 'other'}),
      all,
    );
  });

  test('answers only for the transactions asked about', () async {
    await fileRevision('mine', 'a', metadata: 'a-meta', data: 'a-data');

    expect(
      await driveDao.arDriveTransactionsAmong(['mine'], {'a-data', 'other'}),
      {'a-data'},
    );
    expect(await driveDao.arDriveTransactionsAmong(['mine'], {}), isEmpty);
  });

  test('asks about any number, a batch at a time', () async {
    await fileRevision('mine', 'a', metadata: 'a-meta', data: 'a-data');
    await fileRevision('mine', 'b', metadata: 'b-meta', data: 'b-data');

    // More than one batch, with a match in the first and in the last.
    final asked = {
      'a-data',
      for (var i = 0; i < 1000; i++) 'unknown-$i',
      'b-meta',
    };

    expect(
      await driveDao.arDriveTransactionsAmong(['mine'], asked),
      {'a-data', 'b-meta'},
    );
  });

  test('only the drives asked about', () async {
    await fileRevision('mine', 'a', metadata: 'a-meta', data: 'a-data');
    await fileRevision('theirs', 'z', metadata: 'z-meta', data: 'z-data');

    const asked = {'a-meta', 'a-data', 'z-meta', 'z-data'};
    expect(await driveDao.arDriveTransactionsAmong(['mine'], asked),
        {'a-meta', 'a-data'});
    expect(await driveDao.arDriveTransactionsAmong([], asked), isEmpty);
  });
}
