import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SyncProgress copyWith', () {
    test('retains statusMessage when not provided', () {
      final progress = SyncProgress.initial().copyWith(
        statusMessage: 'Loading...',
      );

      final updated = progress.copyWith(drivesCount: 5);

      expect(updated.statusMessage, 'Loading...');
      expect(updated.drivesCount, 5);
    });

    test('clears statusMessage when null is passed explicitly', () {
      final progress = SyncProgress.initial().copyWith(
        statusMessage: 'Loading...',
      );

      final updated = progress.copyWith(statusMessage: null);

      expect(updated.statusMessage, isNull);
    });

    test('retains driveName when not provided', () {
      final progress = SyncProgress.initial().copyWith(
        driveName: 'My Drive',
      );

      final updated = progress.copyWith(drivesCount: 3);

      expect(updated.driveName, 'My Drive');
      expect(updated.drivesCount, 3);
    });

    test('clears driveName when null is passed explicitly', () {
      final progress = SyncProgress.initial().copyWith(
        driveName: 'My Drive',
      );

      final updated = progress.copyWith(driveName: null);

      expect(updated.driveName, isNull);
    });

    test('sets statusMessage from null to a value', () {
      final progress = SyncProgress.initial();
      expect(progress.statusMessage, isNull);

      final updated = progress.copyWith(statusMessage: 'Syncing...');

      expect(updated.statusMessage, 'Syncing...');
    });

    test('sets driveName from null to a value', () {
      final progress = SyncProgress.initial();
      expect(progress.driveName, isNull);

      final updated = progress.copyWith(driveName: 'Test Drive');

      expect(updated.driveName, 'Test Drive');
    });

    test('drive counts start at zero', () {
      final progress = SyncProgress.initial();

      expect(progress.firstTimeSyncDriveCount, 0);
      expect(progress.skippedDriveCount, 0);
    });

    test('sets firstTimeSyncDriveCount and skippedDriveCount', () {
      final progress = SyncProgress.initial().copyWith(
        firstTimeSyncDriveCount: 2,
        skippedDriveCount: 7,
      );

      expect(progress.firstTimeSyncDriveCount, 2);
      expect(progress.skippedDriveCount, 7);
    });

    test('retains the drive counts when not provided', () {
      final progress = SyncProgress.initial().copyWith(
        firstTimeSyncDriveCount: 2,
        skippedDriveCount: 7,
      );

      final updated = progress.copyWith(drivesCount: 9);

      expect(updated.firstTimeSyncDriveCount, 2);
      expect(updated.skippedDriveCount, 7);
      expect(updated.drivesCount, 9);
    });

    test('overwrites each drive count independently', () {
      final progress = SyncProgress.initial().copyWith(
        firstTimeSyncDriveCount: 2,
        skippedDriveCount: 7,
      );

      final updated = progress.copyWith(skippedDriveCount: 0);

      expect(updated.firstTimeSyncDriveCount, 2);
      expect(updated.skippedDriveCount, 0);
    });
  });
}
