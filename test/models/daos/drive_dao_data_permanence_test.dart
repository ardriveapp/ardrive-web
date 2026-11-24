import 'package:ardrive/models/models.dart';
import 'package:drift/drift.dart' show Value;
import 'package:test/test.dart';

import '../../test_utils/utils.dart';

/// What a file's details read to say since when its data is stored for good.
void main() {
  late Database db;
  late DriveDao driveDao;
  const dataTx = 'data-tx';

  setUp(() {
    db = getTestDb();
    driveDao = db.driveDao;
  });

  tearDown(() async => db.close());

  Future<void> addRevision(DateTime at, {required String action}) =>
      db.into(db.fileRevisions).insert(
            FileRevisionsCompanion.insert(
              fileId: 'file',
              driveId: 'drive',
              parentFolderId: 'root',
              name: 'lisbon.jpg',
              metadataTxId: 'meta-${at.toIso8601String()}',
              dataTxId: dataTx,
              size: 1024,
              lastModifiedDate: at,
              dateCreated: Value(at),
              action: action,
            ),
          );

  // What sync does for every revision it finds: the data's row again, with
  // that revision's date.
  Future<void> syncWrites(String status, DateTime revisionDate) =>
      driveDao.insertNewNetworkTransactions([
        NetworkTransactionsCompanion.insert(
          id: dataTx,
          status: Value(status),
          transactionDateCreated: Value(revisionDate),
        ),
      ]);

  test('dates the data by its first revision, not a later rename', () async {
    await addRevision(DateTime(2022, 3, 12), action: RevisionAction.create);
    await syncWrites(TransactionStatus.confirmed, DateTime(2022, 3, 12));
    await addRevision(DateTime(2026, 11, 10), action: RevisionAction.rename);
    await syncWrites(TransactionStatus.confirmed, DateTime(2026, 11, 10));

    final now = await driveDao.watchDataPermanence(dataTx).first;
    expect(now.status, TransactionStatus.confirmed);
    expect(now.firstStored, DateTime(2022, 3, 12));
  });

  test('knows nothing about data it has never seen', () async {
    final now = await driveDao.watchDataPermanence(dataTx).first;
    expect(now.status, isNull);
    expect(now.firstStored, isNull);
  });

  test('follows the data from pending to confirmed', () async {
    await addRevision(DateTime(2026, 11, 24), action: RevisionAction.create);
    await syncWrites(TransactionStatus.pending, DateTime(2026, 11, 24));

    final statuses = driveDao
        .watchDataPermanence(dataTx)
        .map((p) => p.status)
        .distinct()
        .take(2)
        .toList();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await syncWrites(TransactionStatus.confirmed, DateTime(2026, 11, 24));

    expect(await statuses, [
      TransactionStatus.pending,
      TransactionStatus.confirmed,
    ]);
  });
}
