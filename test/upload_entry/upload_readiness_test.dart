import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/upload_entry/domain/upload_readiness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Loaded extends Mock implements DriveDetailLoadSuccess {}

Drive _drive(String id) => Drive(
      id: id,
      rootFolderId: 'root-$id',
      ownerAddress: 'owner',
      name: id,
      privacy: 'private',
      isHidden: false,
      dateCreated: DateTime(2026),
      lastUpdated: DateTime(2026),
    );

/// What the upload dialog says about one drive, from what the explorer and
/// the sync report.
void main() {
  final photos = _drive('photos');
  final other = _drive('other');

  DriveDetailLoadSuccess loaded(Drive drive, {bool writable = true}) {
    final state = _Loaded();
    when(() => state.currentDrive).thenReturn(drive);
    when(() => state.hasWritePermissions).thenReturn(writable);
    return state;
  }

  UploadReadiness readinessOf(
    DriveDetailState detailState, {
    SyncState? syncState,
    String? syncingDriveId,
  }) =>
      uploadReadiness(
        driveId: photos.id,
        detailState: detailState,
        syncState: syncState ?? SyncIdle(),
        syncingDriveId: syncingDriveId,
      );

  group('an open drive', () {
    test('is ready when this wallet can add to it', () {
      expect(readinessOf(loaded(photos)), UploadReadiness.ready);
    });

    test('is read-only when it cannot', () {
      expect(
        readinessOf(loaded(photos, writable: false)),
        UploadReadiness.readOnly,
      );
    });

    test('is somewhere else when it is not the drive asked about', () {
      expect(readinessOf(loaded(other)), UploadReadiness.elsewhere);
    });
  });

  group('a drive nothing has read', () {
    test('needs a sync', () {
      expect(
        readinessOf(DriveDetailLoadUnsynced(drive: photos)),
        UploadReadiness.needsSync,
      );
    });

    test('says so differently once a sync has found nothing', () {
      expect(
        readinessOf(
          DriveDetailLoadUnsynced(drive: photos, syncFoundNothing: true),
        ),
        UploadReadiness.syncFoundNothing,
      );
    });

    /// One sync at a time, and nothing queues behind it. The drive's own card
    /// holds its Sync button on exactly this.
    test('waits while another drive syncs', () {
      expect(
        readinessOf(
          DriveDetailLoadUnsynced(drive: photos),
          syncState: SyncInProgress(),
          syncingDriveId: other.id,
        ),
        UploadReadiness.needsSyncAfterOtherSync,
      );
    });

    test('holds Check Again as well while another drive syncs', () {
      expect(
        readinessOf(
          DriveDetailLoadUnsynced(drive: photos, syncFoundNothing: true),
          syncState: SyncInProgress(),
          syncingDriveId: other.id,
        ),
        UploadReadiness.needsSyncAfterOtherSync,
      );
    });

    test('is syncing when the running sync is its own', () {
      expect(
        readinessOf(
          DriveDetailLoadUnsynced(drive: photos),
          syncState: SyncInProgress(),
          syncingDriveId: photos.id,
        ),
        UploadReadiness.syncing,
      );
    });

    test('is somewhere else when it is not the drive asked about', () {
      expect(
        readinessOf(DriveDetailLoadUnsynced(drive: other)),
        UploadReadiness.elsewhere,
      );
    });
  });

  group('a drive being opened', () {
    test('is syncing while its own sync runs', () {
      expect(
        readinessOf(
          DriveDetailLoadInProgress(),
          syncState: SyncInProgress(),
          syncingDriveId: photos.id,
        ),
        UploadReadiness.syncing,
      );
    });

    test('is syncing while a sync of every drive runs', () {
      expect(
        readinessOf(DriveDetailLoadInProgress(), syncState: SyncInProgress()),
        UploadReadiness.syncing,
      );
    });

    test('is only opening while no sync touches it', () {
      expect(
        readinessOf(DriveDetailLoadInProgress()),
        UploadReadiness.opening,
      );
      expect(
        readinessOf(
          DriveDetailLoadInProgress(),
          syncState: SyncInProgress(),
          syncingDriveId: other.id,
        ),
        UploadReadiness.opening,
      );
    });

    test('is opening from the initial load as well', () {
      expect(readinessOf(DriveInitialLoading()), UploadReadiness.opening);
    });
  });

  test('has nothing to say once the screen shows no drive', () {
    expect(
      readinessOf(DriveDetailLoadNotFound()),
      UploadReadiness.elsewhere,
    );
    expect(readinessOf(DriveDetailLoadEmpty()), UploadReadiness.elsewhere);
    expect(
      readinessOf(DriveDetailDrivesUnavailable()),
      UploadReadiness.elsewhere,
    );
  });
}
