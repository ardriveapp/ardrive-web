import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/upload_entry/domain/drive_wait.dart';
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

/// What an upload does about the drive it is headed for.
///
/// The rule underneath all of it: an upload waits for a drive to open, never
/// for a drive to sync. A sync takes minutes, the reader moves on, and a
/// dialog arriving afterwards would be reaching back for an action they have
/// left behind.
void main() {
  final photos = _drive('photos');
  final other = _drive('other');

  DriveDetailLoadSuccess loaded(Drive drive, {bool writable = true}) {
    final state = _Loaded();
    when(() => state.currentDrive).thenReturn(drive);
    when(() => state.hasWritePermissions).thenReturn(writable);
    return state;
  }

  DriveWait waitFor(
    DriveDetailState detailState, {
    SyncState? syncState,
    String? syncingDriveId,
    Set<String>? runDriveIds,
  }) =>
      driveWait(
        driveId: photos.id,
        detailState: detailState,
        syncState: syncState ?? SyncIdle(),
        syncingDriveId: syncingDriveId,
        runDriveIds: runDriveIds,
      );

  group('an open drive', () {
    test('is where the reader chooses files', () {
      expect(waitFor(loaded(photos)), DriveWait.ready);
    });

    test('that this wallet cannot add to is dropped', () {
      expect(waitFor(loaded(photos, writable: false)), DriveWait.forget);
    });

    test('that is not the one asked about is dropped', () {
      expect(waitFor(loaded(other)), DriveWait.forget);
    });
  });

  group('a drive nothing has read', () {
    /// The reader asked to upload here, so the drive is read. The page
    /// reports that sync the way it reports every other one.
    test('is synced', () {
      expect(
        waitFor(DriveDetailLoadUnsynced(drive: photos)),
        DriveWait.sync,
      );
    });

    /// One sync at a time, and no queue. Asking now would be refused, so the
    /// press says so instead of looking ignored.
    test('says so when another drive is already syncing', () {
      expect(
        waitFor(
          DriveDetailLoadUnsynced(drive: photos),
          syncState: SyncInProgress(),
          syncingDriveId: other.id,
        ),
        DriveWait.syncBusy,
      );
    });

    /// Minutes, not seconds. The reader comes back and presses Upload again.
    /// Dropped, but said: a press that silently does nothing is the
    /// problem this whole change is about.
    test('says its own sync is already running, and waits for nothing', () {
      expect(
        waitFor(
          DriveDetailLoadUnsynced(drive: photos),
          syncState: SyncInProgress(),
          syncingDriveId: photos.id,
        ),
        DriveWait.syncing,
      );
    });

    /// A refresh of the drive list reads the drives table, not the drive.
    /// The drive's own Sync card may start a sync during one, and so may
    /// this.
    test('reads it during a refresh of the drive list, as its card would', () {
      expect(
        waitFor(
          DriveDetailLoadUnsynced(drive: photos),
          syncState: SyncLoadingDrives(),
        ),
        DriveWait.sync,
      );
    });

    test('drops the upload when a sync already found nothing', () {
      expect(
        waitFor(
          DriveDetailLoadUnsynced(drive: photos, syncFoundNothing: true),
        ),
        DriveWait.forget,
      );
    });

    test('that is not the one asked about is dropped', () {
      expect(waitFor(DriveDetailLoadUnsynced(drive: other)), DriveWait.forget);
    });
  });

  group('a drive being opened', () {
    /// A local read, and over in a moment. This is the only wait an upload
    /// sits through, and it is what carries an upload from the drive chooser
    /// into the drive.
    test('is waited for', () {
      expect(waitFor(DriveDetailLoadInProgress()), DriveWait.wait);
      expect(waitFor(DriveInitialLoading()), DriveWait.wait);
    });

    test('is not waited for while a sync is writing it, and says so', () {
      expect(
        waitFor(
          DriveDetailLoadInProgress(),
          syncState: SyncInProgress(),
          syncingDriveId: photos.id,
        ),
        DriveWait.syncing,
      );
    });

    /// Opening a folder never hangs behind a drive-list refresh:
    /// `waitCurrentSync` counts one as finished. So the upload waits the
    /// second or two it takes, rather than being dropped with a message
    /// about a sync that is not happening.
    test('is waited for through a refresh of the drive list', () {
      expect(
        waitFor(
          DriveDetailLoadInProgress(),
          syncState: SyncLoadingDrives(),
        ),
        DriveWait.wait,
      );
    });

    test('is still waited for while another drive syncs', () {
      expect(
        waitFor(
          DriveDetailLoadInProgress(),
          syncState: SyncInProgress(),
          syncingDriveId: other.id,
        ),
        DriveWait.wait,
      );
    });
  });

  test('a screen showing no drive drops the upload', () {
    expect(waitFor(DriveDetailLoadNotFound()), DriveWait.forget);
    expect(waitFor(DriveDetailLoadEmpty()), DriveWait.forget);
    expect(waitFor(DriveDetailDrivesUnavailable()), DriveWait.forget);
  });
}
