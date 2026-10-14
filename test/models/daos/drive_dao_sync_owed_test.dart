import 'package:ardrive/models/models.dart';
import 'package:drift/drift.dart';
import 'package:test/test.dart';

import '../../test_utils/utils.dart';

/// The two local reads the login decision turns on.
///
/// Nothing exercised them before: inverting the pending filter to `confirmed`
/// - which reverses the feature exactly, syncing when there is nothing to do
/// and never syncing when work is outstanding - left the whole suite green.
void main() {
  late Database db;
  late DriveDao driveDao;

  setUp(() {
    db = getTestDb();
    driveDao = db.driveDao;
  });

  tearDown(() async => db.close());

  group('hasPendingTransactions', () {
    test('is false with nothing stored', () async {
      expect(await driveDao.hasPendingTransactions(), isFalse);
    });

    test('is true while an upload is unresolved', () async {
      await db.into(db.networkTransactions).insert(
            NetworkTransactionsCompanion.insert(
              id: 'tx-pending',
              status: const Value(TransactionStatus.pending),
            ),
          );

      expect(await driveDao.hasPendingTransactions(), isTrue);
    });

    test('is false once it is confirmed, and false when it failed', () async {
      for (final status in [
        TransactionStatus.confirmed,
        TransactionStatus.failed,
      ]) {
        await db.into(db.networkTransactions).insert(
              NetworkTransactionsCompanion.insert(
                id: 'tx-$status',
                status: Value(status),
              ),
            );
      }

      // Resolved either way is work that is over - neither should sync.
      expect(await driveDao.hasPendingTransactions(), isFalse);
    });
  });
}
