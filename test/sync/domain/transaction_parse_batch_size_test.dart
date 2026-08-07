import 'package:ardrive/sync/domain/repositories/sync_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('calculateTransactionParseBatchSize', () {
    test('gives the full budget to a single drive', () {
      expect(
        calculateTransactionParseBatchSize(
          drivesCount: 1,
          drivesSynced: 0,
          maxConcurrentDriveSyncs: 50,
        ),
        200,
      );
    });

    test('splits the budget across remaining drives (below the bound)', () {
      expect(
        calculateTransactionParseBatchSize(
          drivesCount: 4,
          drivesSynced: 0,
          maxConcurrentDriveSyncs: 50,
        ),
        50,
      );
      expect(
        calculateTransactionParseBatchSize(
          drivesCount: 4,
          drivesSynced: 2,
          maxConcurrentDriveSyncs: 50,
        ),
        100,
      );
    });

    test(
        'divides by the concurrency bound, not total remaining, once the '
        'account exceeds it (the fix — 200 drives at 50-wide gives 4, not 1)',
        () {
      expect(
        calculateTransactionParseBatchSize(
          drivesCount: 200,
          drivesSynced: 0,
          maxConcurrentDriveSyncs: 50,
        ),
        4,
      );
      // Even more drives: still bounded by the concurrency, so still 4.
      expect(
        calculateTransactionParseBatchSize(
          drivesCount: 1000,
          drivesSynced: 0,
          maxConcurrentDriveSyncs: 50,
        ),
        4,
      );
    });

    test('uses remaining drives when they are fewer than the bound', () {
      // 10 remaining, 50-wide bound -> divide by 10.
      expect(
        calculateTransactionParseBatchSize(
          drivesCount: 10,
          drivesSynced: 0,
          maxConcurrentDriveSyncs: 50,
        ),
        20,
      );
    });

    test('never returns 0 for wallets with 200 or more drives', () {
      for (final drivesCount in [200, 201, 250, 1000]) {
        expect(
          calculateTransactionParseBatchSize(
            drivesCount: drivesCount,
            drivesSynced: 0,
            maxConcurrentDriveSyncs: 50,
          ),
          greaterThanOrEqualTo(1),
          reason: 'batch size must stay positive for $drivesCount drives',
        );
      }
    });

    test('stays positive even with a degenerate concurrency value', () {
      expect(
        calculateTransactionParseBatchSize(
          drivesCount: 100,
          drivesSynced: 0,
          maxConcurrentDriveSyncs: 0,
        ),
        greaterThanOrEqualTo(1),
      );
    });

    test('never divides by zero when all drives are synced', () {
      expect(
        calculateTransactionParseBatchSize(
          drivesCount: 5,
          drivesSynced: 5,
          maxConcurrentDriveSyncs: 50,
        ),
        200,
      );
    });

    test('never divides by zero when synced exceeds count', () {
      expect(
        calculateTransactionParseBatchSize(
          drivesCount: 5,
          drivesSynced: 6,
          maxConcurrentDriveSyncs: 50,
        ),
        200,
      );
    });
  });
}
