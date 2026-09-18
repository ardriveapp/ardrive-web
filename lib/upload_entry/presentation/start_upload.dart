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
import 'package:ardrive/upload_entry/presentation/upload_destination_dialog.dart';
import 'package:ardrive/upload_entry/presentation/upload_ready_dialog.dart';
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

    case UploadWhenOpen(:final driveId, :final drive):
      final record = drive ??
          await context
              .read<DriveDao>()
              .driveById(driveId: driveId)
              .getSingleOrNull();

      if (record == null || !context.mounted) {
        return;
      }

      await showUploadReadyDialog(
        context,
        drive: record,
        isFolderUpload: isFolderUpload,
      );

    case UploadIntoDrive(:final drive):
      _openForUpload(router, drivesCubit, drive.id, isFolderUpload);

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
          onSelect: (drive) =>
              _openForUpload(router, drivesCubit, drive.id, isFolderUpload),
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
    content: MultiBlocProvider(
      // Handed in rather than looked up: a dialog does not sit under the page
      // that opened it.
      providers: [
        BlocProvider.value(value: context.read<DriveDetailCubit>()),
        BlocProvider.value(value: context.read<SyncCubit>()),
      ],
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
void _openForUpload(
  AppRouterDelegate router,
  DrivesCubit drivesCubit,
  String driveId,
  bool isFolderUpload,
) {
  router.requestUpload(
    UploadRequest(driveId: driveId, isFolderUpload: isFolderUpload),
  );
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
