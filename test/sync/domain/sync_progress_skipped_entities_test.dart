import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DriveEntityHistory.skippedTxIds', () {
    test('defaults to empty so existing callers are unaffected', () {
      final history = DriveEntityHistory(100, []);
      expect(history.skippedTxIds, isEmpty);
    });

    test('carries the skipped transaction ids out of the arweave service', () {
      final history = DriveEntityHistory(100, [], skippedTxIds: ['tx-a']);
      expect(history.skippedTxIds, ['tx-a']);
    });
  });

  group('SyncProgress skipped-entity reporting', () {
    test('defaults to nothing skipped', () {
      final progress = SyncProgress.initial();

      expect(progress.skippedEntityCount, 0);
      expect(progress.skippedEntityTxIdsByDrive, isEmpty);
      expect(progress.skippedEntityTxIds, isEmpty);
      expect(progress.hasSkippedEntities, isFalse);
    });

    test('reports the count and the tx ids keyed by drive', () {
      final progress = SyncProgress.initial().copyWith(
        skippedEntityCount: 3,
        skippedEntityTxIdsByDrive: {
          'drive-1': ['tx-a', 'tx-b'],
          'drive-2': ['tx-c'],
        },
      );

      expect(progress.skippedEntityCount, 3);
      expect(progress.hasSkippedEntities, isTrue);
      expect(progress.skippedEntityTxIdsByDrive['drive-1'], ['tx-a', 'tx-b']);
      expect(progress.skippedEntityTxIdsByDrive['drive-2'], ['tx-c']);
      expect(
        progress.skippedEntityTxIds,
        containsAll(<String>['tx-a', 'tx-b', 'tx-c']),
      );
    });

    test('skipped entities are independent of drive-level query failures', () {
      // A drive can sync "successfully" while still dropping entities, so the
      // skip count must not be inferred from failedQueries.
      final progress = SyncProgress.initial().copyWith(
        skippedEntityCount: 1,
        skippedEntityTxIdsByDrive: {
          'drive-1': ['tx-a'],
        },
      );

      expect(progress.hasErrors, isFalse);
      expect(progress.hasSkippedEntities, isTrue);
    });

    test('copyWith preserves skipped data when not overridden', () {
      final progress = SyncProgress.initial().copyWith(
        skippedEntityCount: 2,
        skippedEntityTxIdsByDrive: {
          'drive-1': ['tx-a', 'tx-b'],
        },
      );

      final later = progress.copyWith(progress: 1.0);

      expect(later.skippedEntityCount, 2);
      expect(later.skippedEntityTxIdsByDrive['drive-1'], ['tx-a', 'tx-b']);
    });
  });
}
