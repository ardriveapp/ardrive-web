import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/upload_entry/domain/upload_wait.dart';
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

  UploadWait waitFor(
    DriveDetailState detailState, {
    SyncState? syncState,
    String? syncingDriveId,
  }) =>
      uploadWait(
        driveId: photos.id,
        detailState: detailState,
        syncState: syncState ?? SyncIdle(),
        syncingDriveId: syncingDriveId,
      );

  group('an open drive', () {
    test('is where the reader chooses files', () {
      expect(waitFor(loaded(photos)), UploadWait.choose);
    });

    test('that this wallet cannot add to is dropped', () {
      expect(waitFor(loaded(photos, writable: false)), UploadWait.forget);
    });

    test('that is not the one asked about is dropped', () {
      expect(waitFor(loaded(other)), UploadWait.forget);
    });
  });

  group('a drive nothing has read', () {
    /// The reader asked to upload here, so the drive is read. The page
    /// reports that sync the way it reports every other one.
    test('is synced', () {
      expect(
        waitFor(DriveDetailLoadUnsynced(drive: photos)),
        UploadWait.sync,
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
        UploadWait.syncBusy,
      );
    });

    /// Minutes, not seconds. The reader comes back and presses Upload again.
    test('drops the upload when its own sync is already running', () {
      expect(
        waitFor(
          DriveDetailLoadUnsynced(drive: photos),
          syncState: SyncInProgress(),
          syncingDriveId: photos.id,
        ),
        UploadWait.forget,
      );
    });

    test('drops the upload when a sync already found nothing', () {
      expect(
        waitFor(
          DriveDetailLoadUnsynced(drive: photos, syncFoundNothing: true),
        ),
        UploadWait.forget,
      );
    });

    test('that is not the one asked about is dropped', () {
      expect(waitFor(DriveDetailLoadUnsynced(drive: other)), UploadWait.forget);
    });
  });

  group('a drive being opened', () {
    /// A local read, and over in a moment. This is the only wait an upload
    /// sits through, and it is what carries an upload from the drive chooser
    /// into the drive.
    test('is waited for', () {
      expect(waitFor(DriveDetailLoadInProgress()), UploadWait.wait);
      expect(waitFor(DriveInitialLoading()), UploadWait.wait);
    });

    test('is not waited for while a sync is writing it', () {
      expect(
        waitFor(
          DriveDetailLoadInProgress(),
          syncState: SyncInProgress(),
          syncingDriveId: photos.id,
        ),
        UploadWait.forget,
      );
    });

    test('is still waited for while another drive syncs', () {
      expect(
        waitFor(
          DriveDetailLoadInProgress(),
          syncState: SyncInProgress(),
          syncingDriveId: other.id,
        ),
        UploadWait.wait,
      );
    });
  });

  test('a screen showing no drive drops the upload', () {
    expect(waitFor(DriveDetailLoadNotFound()), UploadWait.forget);
    expect(waitFor(DriveDetailLoadEmpty()), UploadWait.forget);
    expect(waitFor(DriveDetailDrivesUnavailable()), UploadWait.forget);
  });
}
