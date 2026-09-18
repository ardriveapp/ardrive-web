import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';

/// Where an upload to one drive stands, as the upload dialog tells it.
///
/// Every value but [elsewhere] has a next step the reader can take or watch.
/// That is the point of the dialog: pressing Upload never ends in silence.
enum UploadReadiness {
  /// Open, and this wallet can add to it. Next: choose files.
  ready,

  /// Open, but somebody else's. Nothing in the dialog can change that.
  readOnly,

  /// Nothing on this device has read it yet, and nothing is reading it now.
  needsSync,

  /// As [needsSync], but another drive is syncing, and only one sync runs at
  /// a time. Nothing is queued: the dialog says so and leaves the choice with
  /// the reader.
  needsSyncAfterOtherSync,

  /// A sync ran and found nothing for this drive on chain yet.
  syncFoundNothing,

  /// Being synced now.
  syncing,

  /// Being opened, with no sync involved.
  opening,

  /// The screen has moved on to something that is not this drive.
  elsewhere,
}

/// Reads [UploadReadiness] off the explorer's state for [driveId].
///
/// Pure, and reading only what the dialog already watches, so every state can
/// be checked without standing a dialog up.
UploadReadiness uploadReadiness({
  required String driveId,
  required DriveDetailState detailState,
  required SyncState syncState,
  required String? syncingDriveId,
  Iterable<String> completedDriveIds = const [],
  Set<String>? runDriveIds,
}) {
  final syncTouchesThisDrive = SyncCubit.syncTouchesDrive(
    state: syncState,
    syncingDriveId: syncingDriveId,
    driveId: driveId,
    completedDriveIds: completedDriveIds,
    runDriveIds: runDriveIds,
  );

  if (detailState is DriveDetailLoadSuccess) {
    if (detailState.currentDrive.id != driveId) {
      return UploadReadiness.elsewhere;
    }

    return detailState.hasWritePermissions
        ? UploadReadiness.ready
        : UploadReadiness.readOnly;
  }

  if (detailState is DriveDetailLoadUnsynced) {
    if (detailState.drive.id != driveId) {
      return UploadReadiness.elsewhere;
    }

    if (syncTouchesThisDrive) {
      return UploadReadiness.syncing;
    }

    // The test the drive's own card uses to hold its Sync button: the cubit
    // refuses a second sync outright, so offering one would be a button that
    // does nothing.
    if (syncState is SyncInProgress) {
      return UploadReadiness.needsSyncAfterOtherSync;
    }

    return detailState.syncFoundNothing
        ? UploadReadiness.syncFoundNothing
        : UploadReadiness.needsSync;
  }

  // Neither state names a drive. The dialog was opened for [driveId], and the
  // explorer cannot switch drives underneath a modal, so this is that drive.
  if (detailState is DriveDetailLoadInProgress ||
      detailState is DriveInitialLoading) {
    return syncTouchesThisDrive
        ? UploadReadiness.syncing
        : UploadReadiness.opening;
  }

  return UploadReadiness.elsewhere;
}
