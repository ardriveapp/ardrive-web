import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';

/// What an upload should do about the drive it is headed for.
///
/// Pressing Upload on a drive nothing has read is a request to upload there,
/// not a request to watch a sync. The sync starts and the page reports it the
/// way it reports every other sync: the drive's own card, the progress in the
/// top bar. Nothing here draws a second report over the top of that.
///
/// The upload itself does not survive that sync. A sync takes as long as it
/// takes, the reader goes and does something else, and a dialog arriving
/// afterwards would be reaching back for an action they have moved on from.
/// They come back to a drive that opens, press Upload, and go straight to the
/// picker. Only the second or two a drive takes to open is worth waiting
/// through, which is what [UploadWait.wait] covers.
enum UploadWait {
  /// The drive is open. Ask the reader to choose files.
  choose,

  /// Nothing has read the drive and nothing is reading it. Read it, because
  /// the reader asked to upload here, and let the page report it.
  sync,

  /// A sync is already running and nothing queues behind it. Say so, since
  /// pressing Upload has to answer for itself.
  syncBusy,

  /// The drive is opening. Worth waiting through.
  wait,

  /// Nothing more to do for this upload.
  forget,
}

/// Reads [UploadWait] for [driveId] off the explorer and the sync.
///
/// Pure, so every path an upload can take is checked without a widget or a
/// router.
UploadWait uploadWait({
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
      // Another drive is on screen, so this is not what the reader is doing
      // any more.
      return UploadWait.forget;
    }

    return detailState.hasWritePermissions
        ? UploadWait.choose
        : UploadWait.forget;
  }

  if (detailState is DriveDetailLoadUnsynced) {
    if (detailState.drive.id != driveId) {
      return UploadWait.forget;
    }

    // Already being read. That is a wait of minutes, not seconds, so the
    // upload is dropped rather than left to arrive over whatever comes next.
    if (syncTouchesThisDrive) {
      return UploadWait.forget;
    }

    // The sync ran and found nothing on chain for this drive. Running it
    // again on the reader's behalf would find nothing again, and the card
    // already says so and offers Check Again.
    if (detailState.syncFoundNothing) {
      return UploadWait.forget;
    }

    // One sync at a time, and no queue: asking now would be refused, and a
    // refusal nobody can see is the silence this whole change is about.
    if (syncState is SyncInProgress) {
      return UploadWait.syncBusy;
    }

    return UploadWait.sync;
  }

  if (detailState is DriveDetailLoadInProgress ||
      detailState is DriveInitialLoading) {
    // Opening because a sync is writing it is the long wait again.
    return syncTouchesThisDrive ? UploadWait.forget : UploadWait.wait;
  }

  return UploadWait.forget;
}
