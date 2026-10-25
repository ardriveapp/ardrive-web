import 'package:ardrive/models/models.dart';
import 'package:drift/drift.dart';
import 'package:test/test.dart';

import '../../test_utils/utils.dart';

/// What the permanence panel says is stored for good. A figure somebody may
/// hold us to, so it counts only data that is really there, once.
void main() {
  late Database db;
  late DriveDao driveDao;

  setUp(() {
    db = getTestDb();
    driveDao = db.driveDao;
  });

  tearDown(() async => db.close());

  /// One revision of [fileId], made in [year] (in [month], so a file's
  /// revisions in the same year stay apart).
  Future<void> addRevision(
    String fileId, {
    required int size,
    String driveId = 'drive',
    String? dataTxId,
    int year = 2024,
    int month = 6,
    String? pinnedBy,
  }) =>
      db.into(db.fileRevisions).insert(
            FileRevisionsCompanion.insert(
              fileId: fileId,
              driveId: driveId,
              parentFolderId: 'root',
              name: fileId,
              metadataTxId: '$fileId-$year-$month-meta',
              dataTxId: dataTxId ?? '$fileId-tx',
              size: size,
              lastModifiedDate: DateTime(year),
              dateCreated: Value(DateTime(year, month)),
              action: RevisionAction.create,
              pinnedDataOwnerAddress: Value(pinnedBy),
            ),
          );

  Future<void> markTx(String txId, String status) =>
      db.into(db.networkTransactions).insert(
            NetworkTransactionsCompanion.insert(
              id: txId,
              status: Value(status),
            ),
          );

  test('groups what is stored by the year it was uploaded', () async {
    await addRevision('a', size: 100, year: 2022);
    await addRevision('b', size: 200, year: 2024);
    await addRevision('c', size: 50, year: 2024);

    expect(await driveDao.permanentDataByYear(['drive']), {
      2022: const PermanentData(bytes: 100, items: 1),
      2024: const PermanentData(bytes: 250, items: 2),
    });
    expect(await driveDao.permanentFileCount(['drive']), 3);
  });

  test('counts every version of a file, each in the year it was uploaded',
      () async {
    // Made in 2021, replaced in 2024: both versions are stored, and the
    // second is 2024's, not 2021's.
    await addRevision('report', size: 100, dataTxId: 'v1', year: 2021);
    await addRevision('report', size: 300, dataTxId: 'v2', year: 2024);

    expect(await driveDao.permanentDataByYear(['drive']), {
      2021: const PermanentData(bytes: 100, items: 1),
      2024: const PermanentData(bytes: 300, items: 1),
    });
    expect(await driveDao.permanentFileCount(['drive']), 1);
  });

  test('counts a rename once, in the year its data came', () async {
    // A rename is a new revision over the same data.
    await addRevision('photo', size: 100, dataTxId: 'data', year: 2022);
    await addRevision('photo', size: 100, dataTxId: 'data', year: 2024);

    expect(await driveDao.permanentDataByYear(['drive']), {
      2022: const PermanentData(bytes: 100, items: 1),
    });
  });

  test('counts a copy of the same data once, though it is two files', () async {
    // The same upload, filed in two folders.
    await addRevision('original', size: 100, dataTxId: 'shared', year: 2022);
    await addRevision('copy', size: 100, dataTxId: 'shared', year: 2024);

    expect(await driveDao.permanentDataByYear(['drive']), {
      2022: const PermanentData(bytes: 100, items: 1),
    });
    expect(await driveDao.permanentFileCount(['drive']), 2);
  });

  test('leaves out uploads that are pending or failed', () async {
    await addRevision('landed', size: 100);
    await addRevision('waiting', size: 200);
    await addRevision('lost', size: 400);
    await markTx('landed-tx', TransactionStatus.confirmed);
    await markTx('waiting-tx', TransactionStatus.pending);
    await markTx('lost-tx', TransactionStatus.failed);

    expect(await driveDao.permanentDataByYear(['drive']), {
      2024: const PermanentData(bytes: 100, items: 1),
    });
    expect(await driveDao.permanentFileCount(['drive']), 1);
  });

  test('keeps a file whose newest version is still uploading', () async {
    await addRevision('draft', size: 100, dataTxId: 'old', year: 2023);
    await addRevision('draft', size: 200, dataTxId: 'new', year: 2024);
    await markTx('new', TransactionStatus.pending);

    expect(await driveDao.permanentDataByYear(['drive']), {
      2023: const PermanentData(bytes: 100, items: 1),
    });
    expect(await driveDao.permanentFileCount(['drive']), 1);
  });

  test('counts data synced with no transaction row as stored', () async {
    // A sync writes revisions before, or without, their transaction rows.
    await addRevision('synced', size: 100);

    expect(await driveDao.permanentDataByYear(['drive']), {
      2024: const PermanentData(bytes: 100, items: 1),
    });
  });

  test('leaves out pinned files, which somebody else paid to store', () async {
    await addRevision('mine', size: 100);
    await addRevision('pin', size: 9000, pinnedBy: 'someone-else');

    expect(await driveDao.permanentDataByYear(['drive']), {
      2024: const PermanentData(bytes: 100, items: 1),
    });
    expect(await driveDao.permanentFileCount(['drive']), 1);
  });

  test('reads only the drives asked about', () async {
    await addRevision('mine', size: 100, driveId: 'mine');
    await addRevision('shared-with-me', size: 9000, driveId: 'theirs');

    expect(await driveDao.permanentDataByYear(['mine']), {
      2024: const PermanentData(bytes: 100, items: 1),
    });
    expect(await driveDao.permanentFileCount(['mine']), 1);
    expect(await driveDao.permanentDataByYear([]), isEmpty);
    expect(await driveDao.permanentFileCount([]), 0);
  });

  group('the data version', () {
    // The profile card keeps its figures while this stays the same, so it
    // must change whenever they could.
    test('changes when a revision is written', () async {
      final before = await driveDao.permanentDataVersion();
      await addRevision('new', size: 100);

      expect(await driveDao.permanentDataVersion(), isNot(before));
    });

    test('changes when an upload lands or fails', () async {
      await addRevision('a', size: 100);
      await addRevision('b', size: 100);
      await markTx('a-tx', TransactionStatus.pending);
      await markTx('b-tx', TransactionStatus.pending);
      final pending = await driveDao.permanentDataVersion();

      Future<void> settle(String txId, String status) =>
          (db.update(db.networkTransactions)..where((t) => t.id.equals(txId)))
              .write(NetworkTransactionsCompanion(status: Value(status)));

      await settle('a-tx', TransactionStatus.failed);
      final oneFailed = await driveDao.permanentDataVersion();
      expect(oneFailed, isNot(pending));

      await settle('b-tx', TransactionStatus.confirmed);
      expect(await driveDao.permanentDataVersion(), isNot(oneFailed));
    });

    test('stays the same while nothing changes', () async {
      await addRevision('a', size: 100);

      expect(
        await driveDao.permanentDataVersion(),
        await driveDao.permanentDataVersion(),
      );
    });

    // The open profile card follows this to count again when the gateway
    // confirms what a sync wrote as pending.
    test('can be watched, and moves when an upload lands', () async {
      await addRevision('a', size: 100);
      await markTx('a-tx', TransactionStatus.pending);

      final versions = <String>[];
      final subscription =
          driveDao.watchPermanentDataVersion().listen(versions.add);
      await pumpEventQueue();

      await (db.update(db.networkTransactions)
            ..where((t) => t.id.equals('a-tx')))
          .write(const NetworkTransactionsCompanion(
              status: Value(TransactionStatus.confirmed)));
      await pumpEventQueue();
      await subscription.cancel();

      expect(versions.toSet(), hasLength(2));
      expect(versions.last, await driveDao.permanentDataVersion());
    });
  });

  group('pending data', () {
    // What a first sync leaves behind until the gateway answers: every file
    // written with its data pending, so none of them is counted yet.
    test("is there while a file's data waits to be confirmed", () async {
      await addRevision('a', size: 100);
      await markTx('a-tx', TransactionStatus.pending);

      expect(await driveDao.permanentFileCount(['drive']), 0);
      expect(await driveDao.hasPendingData(['drive']), isTrue);
    });

    test('is gone once it is confirmed, or when it failed', () async {
      await addRevision('a', size: 100);
      await addRevision('b', size: 100);
      await markTx('a-tx', TransactionStatus.confirmed);
      await markTx('b-tx', TransactionStatus.failed);

      expect(await driveDao.hasPendingData(['drive']), isFalse);
    });

    test('belongs to the drives asked about, and not to a pin', () async {
      await addRevision('theirs', size: 100, driveId: 'other');
      await markTx('theirs-tx', TransactionStatus.pending);
      await addRevision('pin', size: 100, pinnedBy: 'someone');
      await markTx('pin-tx', TransactionStatus.pending);

      expect(await driveDao.hasPendingData(['drive']), isFalse);
      expect(await driveDao.hasPendingData([]), isFalse);
    });

    test('is not data synced from the network with no row of its own',
        () async {
      await addRevision('a', size: 100);

      expect(await driveDao.hasPendingData(['drive']), isFalse);
    });
  });
}
