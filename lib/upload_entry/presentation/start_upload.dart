import 'dart:async';

import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/components/drive_create_form.dart';
import 'package:ardrive/components/upload_form.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/upload_entry/domain/upload_request.dart';
import 'package:ardrive/upload_entry/domain/upload_start.dart';
import 'package:ardrive/upload_entry/domain/drive_wait.dart';
import 'package:ardrive/upload_entry/presentation/upload_destination_dialog.dart';
import 'package:ardrive/upload_entry/presentation/upload_ready_dialog.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Pressing Upload, from anywhere it can be pressed.
///
/// Inside an open drive this is the ordinary upload, untouched. Everywhere
/// else it leads to the drive the files will go to, and from there to the
/// same upload - nothing after `promptToUpload` knows how the reader arrived.
///
/// [context] is the control's own, and must sit under the shell's
/// [DriveDetailCubit].
Future<void> startUpload(
  BuildContext context, {
  required bool isFolderUpload,
}) async {
  final router = context.read<AppRouterDelegate>();
  final drivesCubit = context.read<DrivesCubit>();

  final step = decideUploadStart(
    detailState: context.read<DriveDetailCubit>().state,
    showingDrivesList: router.showingDrivesList,
    openDriveId: router.driveId,
    drivesState: drivesCubit.state,
  );

  switch (step) {
    case UploadHere(:final driveId, :final folderId):
      await promptToUpload(
        context,
        driveId: driveId,
        parentFolderId: folderId,
        isFolderUpload: isFolderUpload,
      );

    case UploadWhenOpen(:final driveId):
      final request = UploadRequest(
        driveId: driveId,
        isFolderUpload: isFolderUpload,
      );

      if (actOnUpload(
        context,
        request: request,
        detailState: context.read<DriveDetailCubit>().state,
      )) {
        // Only ever the second or two a drive takes to open; anything longer
        // is dropped rather than left to arrive over something else.
        router.requestUpload(request);
      }

    case UploadIntoDrive(:final drive):
      _openForUpload(context, router, drivesCubit, drive.id, isFolderUpload);

    case UploadChooseDrive(:final drives):
      final unsynced =
          await _unsyncedDriveIds(context.read<DriveDao>(), drives);

      if (!context.mounted) {
        return;
      }

      await showArDriveDialog(
        context,
        content: UploadDestinationDialog(
          drives: drives,
          unsyncedDriveIds: unsynced,
          onSelect: (drive) => _openForUpload(
            context,
            router,
            drivesCubit,
            drive.id,
            isFolderUpload,
          ),
        ),
      );

    case UploadNeedsDrive():
      await showArDriveDialog(
        context,
        content: UploadNeedsDriveDialog(
          onCreateDrive: () {
            if (context.mounted) {
              unawaited(
                _createDriveForUpload(
                  context,
                  router,
                  drivesCubit,
                  isFolderUpload,
                ),
              );
            }
          },
        ),
      );

    case UploadNotYet():
      // Only reachable in the moment before the drive list is known, which
      // is also before the page offers anything to act on.
      logger.d('Upload pressed before the drive list was known');
  }
}

/// Acts on an upload headed for a drive, and says whether it is still waiting.
///
/// The one place that decides what a waiting upload does, so the press and the
/// arrival cannot drift apart. Returns true only while the drive is opening:
/// an upload that would have to outlive a sync is dropped here, and the reader
/// presses Upload again when the drive is ready.
///
/// [context] must sit under the explorer's [DriveDetailCubit].
bool actOnUpload(
  BuildContext context, {
  required UploadRequest request,
  required DriveDetailState detailState,
}) {
  final syncCubit = context.read<SyncCubit>();

  final wait = driveWait(
    driveId: request.driveId,
    detailState: detailState,
    syncState: syncCubit.state,
    syncingDriveId: syncCubit.syncingDriveId,
    completedDriveIds: syncCubit.completedDriveIds,
    runDriveIds: syncCubit.syncingDriveIds,
  );

  switch (wait) {
    case DriveWait.ready:
      showUploadReadyDialog(
        context,
        drive: (detailState as DriveDetailLoadSuccess).currentDrive,
        isFolderUpload: request.isFolderUpload,
      );

      return false;

    case DriveWait.sync:
    case DriveWait.syncBusy:
    case DriveWait.syncing:
      readDriveForAction(context, wait: wait);

      return false;

    case DriveWait.wait:
      return true;

    case DriveWait.forget:
      return false;
  }
}

/// Reads the drive an action needs, or says why it cannot be read now.
///
/// Every item in the New menu that writes into a drive waits on the same
/// thing, so they all arrive here: pressing New Folder on a drive nothing has
/// read starts the same sync that pressing Upload does, and the page reports
/// it the same way. The action itself is not remembered - see [DriveWait].
void readDriveForAction(BuildContext context, {required DriveWait wait}) {
  switch (wait) {
    case DriveWait.sync:
      // The same sync the drive's own card runs.
      context.read<DriveDetailCubit>().syncCurrentDrive();

    case DriveWait.syncBusy:
      // Nothing was started and nothing is queued, so the press answers for
      // itself rather than looking ignored.
      _say(
        context,
        appLocalizationsOf(context).driveSyncNotStartedAnotherDriveIsSyncing,
      );

    case DriveWait.syncing:
      _say(context, appLocalizationsOf(context).driveIsSyncingTryLater);

    case DriveWait.ready:
    case DriveWait.wait:
    case DriveWait.forget:
      break;
  }
}

void _say(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}

/// Reads the drive [driveId] needs for an action pressed in its own menu.
///
/// The menu's own entry point: it knows the drive is in view but not whether
/// it has been read, and this answers that with the sync or with the reason
/// there is none.
void readDriveForMenuAction(BuildContext context, {required String driveId}) {
  final syncCubit = context.read<SyncCubit>();

  readDriveForAction(
    context,
    wait: driveWait(
      driveId: driveId,
      detailState: context.read<DriveDetailCubit>().state,
      syncState: syncCubit.state,
      syncingDriveId: syncCubit.syncingDriveId,
      completedDriveIds: syncCubit.completedDriveIds,
      runDriveIds: syncCubit.syncingDriveIds,
    ),
  );
}

/// The upload dialog for [drive], over the explorer that is showing it.
///
/// [context] must sit under the explorer's [DriveDetailCubit], and stay
/// mounted for as long as the explorer does: the upload itself is started
/// from it once the dialog has closed.
Future<void> showUploadReadyDialog(
  BuildContext context, {
  required Drive drive,
  required bool isFolderUpload,
}) {
  return showArDriveDialog(
    context,
    content: BlocProvider.value(
      // Handed in rather than looked up: a dialog does not sit under the page
      // that opened it.
      value: context.read<DriveDetailCubit>(),
      child: UploadReadyDialog(
        drive: drive,
        isFolderUpload: isFolderUpload,
        onChoose: (folderId) {
          if (!context.mounted) {
            return;
          }

          promptToUpload(
            context,
            driveId: drive.id,
            parentFolderId: folderId,
            isFolderUpload: isFolderUpload,
          );
        },
      ),
    ),
  );
}

/// Opens [driveId] with an upload waiting for it.
///
/// The request goes first: selecting the drive is what opens it, and the
/// explorer looks for the request as soon as the drive reports in.
///
/// Unless a sync is walking that drive. The explorer waits that sync out
/// before it reports anything, which can be minutes, and an upload must not
/// arrive at the end of it. So the reader is told, the drive still opens -
/// that much they did ask for - and nothing waits.
void _openForUpload(
  BuildContext context,
  AppRouterDelegate router,
  DrivesCubit drivesCubit,
  String driveId,
  bool isFolderUpload,
) {
  final syncCubit = context.read<SyncCubit>();
  final beingSynced = syncHoldsDrive(
    driveId: driveId,
    syncState: syncCubit.state,
    syncingDriveId: syncCubit.syncingDriveId,
    completedDriveIds: syncCubit.completedDriveIds,
    runDriveIds: syncCubit.syncingDriveIds,
  );

  if (beingSynced) {
    if (context.mounted) {
      _say(context, appLocalizationsOf(context).driveIsSyncingTryLater);
    }
  } else {
    router.requestUpload(
      UploadRequest(driveId: driveId, isFolderUpload: isFolderUpload),
    );
  }

  drivesCubit.selectDrive(driveId);
}

/// Makes a first drive, and carries the upload into it.
///
/// Creating a drive selects it, and selecting a drive opens it, so the upload
/// only has to be waiting when that selection happens. The drive's id is not
/// known until then, which is why the request is made from the selection
/// rather than before the dialog. Closing the dialog without a drive leaves
/// nothing behind.
Future<void> _createDriveForUpload(
  BuildContext context,
  AppRouterDelegate router,
  DrivesCubit drivesCubit,
  bool isFolderUpload,
) async {
  final subscription = drivesCubit.driveSelections.take(1).listen((driveId) {
    router.requestUpload(
      UploadRequest(driveId: driveId, isFolderUpload: isFolderUpload),
    );
  });

  try {
    await promptToCreateDrive(context);
  } finally {
    await subscription.cancel();
  }
}

/// Which of [drives] nothing on this device has read.
///
/// The test the explorer itself uses: a drive opens once its root folder is
/// in the local database. A drive created on this device has one already,
/// however little has been synced. A lookup that fails marks nothing: the
/// mark is a courtesy, and guessing it wrong is worse than leaving it off.
Future<Set<String>> _unsyncedDriveIds(
  DriveDao driveDao,
  List<Drive> drives,
) async {
  final unsynced = await Future.wait(
    drives.map((drive) async {
      try {
        final root = await driveDao
            .folderById(folderId: drive.rootFolderId)
            .getSingleOrNull();

        return root == null ? drive.id : null;
      } catch (e) {
        logger.d('Could not check whether ${drive.id} has been read: $e');
        return null;
      }
    }),
  );

  return unsynced.whereType<String>().toSet();
}
