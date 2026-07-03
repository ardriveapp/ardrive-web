import 'package:ardrive/sync/domain/repositories/sync_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('calculateTransactionParseBatchSize', () {
    test('gives the full budget to a single drive', () {
      expect(
        calculateTransactionParseBatchSize(drivesCount: 1, drivesSynced: 0),
        200,
      );
    });

    test('splits the budget across remaining drives', () {
      expect(
        calculateTransactionParseBatchSize(drivesCount: 4, drivesSynced: 0),
        50,
      );
      expect(
        calculateTransactionParseBatchSize(drivesCount: 4, drivesSynced: 2),
        100,
      );
    });

    test('never returns 0 for wallets with 200 or more drives', () {
      for (final drivesCount in [200, 201, 250, 1000]) {
        expect(
          calculateTransactionParseBatchSize(
            drivesCount: drivesCount,
            drivesSynced: 0,
          ),
          greaterThanOrEqualTo(1),
          reason: 'batch size must stay positive for $drivesCount drives',
        );
      }
    });

    test('never divides by zero when all drives are synced', () {
      expect(
        calculateTransactionParseBatchSize(drivesCount: 5, drivesSynced: 5),
        200,
      );
    });

    test('never divides by zero when synced exceeds count', () {
      expect(
        calculateTransactionParseBatchSize(drivesCount: 5, drivesSynced: 6),
        200,
      );
    });
  });
}
