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

  Future<void> addFile(
    String fileId, {
    required int size,
    String driveId = 'drive',
    String? dataTxId,
    int year = 2024,
    String? pinnedBy,
  }) =>
      db.into(db.fileEntries).insert(
            FileEntriesCompanion.insert(
              id: fileId,
              driveId: driveId,
              parentFolderId: 'root',
              name: fileId,
              dataTxId: dataTxId ?? '$fileId-tx',
              size: size,
              lastModifiedDate: DateTime(year),
              dateCreated: Value(DateTime(year, 6)),
              path: '',
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
    await addFile('a', size: 100, year: 2022);
    await addFile('b', size: 200, year: 2024);
    await addFile('c', size: 50, year: 2024);

    expect(await driveDao.permanentDataByYear(['drive']), {
      2022: const PermanentData(bytes: 100, items: 1),
      2024: const PermanentData(bytes: 250, items: 2),
    });
  });

  test('counts a copy of the same data once, in the year it first came',
      () async {
    // The same upload, filed in two folders.
    await addFile('original', size: 100, dataTxId: 'shared', year: 2022);
    await addFile('copy', size: 100, dataTxId: 'shared', year: 2024);

    expect(await driveDao.permanentDataByYear(['drive']), {
      2022: const PermanentData(bytes: 100, items: 1),
    });
  });

  test('leaves out uploads that are pending or failed', () async {
    await addFile('landed', size: 100);
    await addFile('waiting', size: 200);
    await addFile('lost', size: 400);
    await markTx('landed-tx', TransactionStatus.confirmed);
    await markTx('waiting-tx', TransactionStatus.pending);
    await markTx('lost-tx', TransactionStatus.failed);

    expect(await driveDao.permanentDataByYear(['drive']), {
      2024: const PermanentData(bytes: 100, items: 1),
    });
  });

  test('counts data synced with no transaction row as stored', () async {
    // A sync writes file rows before, or without, their transaction rows.
    await addFile('synced', size: 100);

    expect(await driveDao.permanentDataByYear(['drive']), {
      2024: const PermanentData(bytes: 100, items: 1),
    });
  });

  test('leaves out pinned files, which somebody else paid to store', () async {
    await addFile('mine', size: 100);
    await addFile('pin', size: 9000, pinnedBy: 'someone-else');

    expect(await driveDao.permanentDataByYear(['drive']), {
      2024: const PermanentData(bytes: 100, items: 1),
    });
  });

  test('reads only the drives asked about', () async {
    await addFile('mine', size: 100, driveId: 'mine');
    await addFile('shared-with-me', size: 9000, driveId: 'theirs');

    expect(await driveDao.permanentDataByYear(['mine']), {
      2024: const PermanentData(bytes: 100, items: 1),
    });
    expect(await driveDao.permanentDataByYear([]), isEmpty);
  });
}
