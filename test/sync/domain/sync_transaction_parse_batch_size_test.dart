import 'package:ardrive/sync/domain/repositories/sync_repository.dart';
import 'package:ardrive/sync/utils/batch_processor.dart';
import 'package:flutter_test/flutter_test.dart';

/// The transaction-parse budget is shared out across the drives left to sync,
/// and the sharing is integer division - so the interesting cases are all at
/// the bottom of the range, where it rounds to nothing.
void main() {
  int sizeFor(int drivesCount, {int drivesSynced = 0}) =>
      SyncRepository.transactionParseBatchSizeFor(
        drivesCount: drivesCount,
        drivesSynced: drivesSynced,
      );

  group('transaction parse batch size', () {
    test('shares the budget across the drives still to sync', () {
      expect(sizeFor(1), SyncRepository.maxTransactionParseBatchSize);
      expect(sizeFor(2), 100);
      expect(sizeFor(4), 50);
      expect(sizeFor(200), 1);
    });

    test('counts only the drives that have not been synced yet', () {
      // Four drives with two already done leaves two to share the budget.
      expect(sizeFor(4, drivesSynced: 2), 100);
    });

    test('never returns zero, however many drives there are', () {
      // The bug this exists for: `200 ~/ remaining` is integer division, so at
      // 201 remaining drives it rounds to zero - and a batch size of zero is
      // not a small batch, it is an ArgumentError out of `BatchProcessor`.
      for (final drives in [201, 500, 5000]) {
        expect(
          sizeFor(drives),
          greaterThan(0),
          reason: '$drives drives must still produce a usable batch size',
        );
      }
    });

    test('the clamped size is one `BatchProcessor` will accept', () async {
      // Tying the two halves together, because the clamp is only correct in
      // terms of what the consumer rejects.
      final batchSize = sizeFor(5000);

      // Consumed, not merely called. `batchProcess` is `async*`, so its
      // `batchSize` guard does not run until something listens - a test that
      // only calls it passes with a batch size of zero, which is the single
      // value the guard exists to reject.
      //
      // The list is mutable because `batchProcess` clears it.
      await expectLater(
        BatchProcessor().batchProcess<int>(
          list: [1, 2, 3],
          batchSize: batchSize,
          endOfBatchCallback: (_) => const Stream<double>.empty(),
        ),
        emitsDone,
      );
    });

    test('a fully synced wallet does not divide by zero', () {
      // `drivesSynced == drivesCount` leaves nothing to divide by. Reachable or
      // not, it throws for the same reason the zero batch did.
      expect(() => sizeFor(3, drivesSynced: 3), returnsNormally);
      expect(sizeFor(3, drivesSynced: 3), greaterThan(0));
    });
  });
}
