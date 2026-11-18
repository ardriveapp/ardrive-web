import 'dart:async';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/components/drive_picker/drive_picker_cubit.dart';
import 'package:ardrive/components/drive_picker/drive_picker_dialog.dart';
import 'package:ardrive/components/upload_form.dart';
import 'package:ardrive/upload_entry/domain/upload_destinations.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/sharing/blocs/sharing_file_bloc.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ardrive/blocs/blocs.dart';

class SharingFileListener extends StatefulWidget {
  const SharingFileListener(
      {super.key, required this.child, required this.context});

  final Widget child;
  final BuildContext context;

  @override
  State<SharingFileListener> createState() => _SharingFileListenerState();
}

class _SharingFileListenerState extends State<SharingFileListener> {
  @override
  void dispose() {
    super.dispose();
  }

  /// One picker for what used to be four screens: the drive and then the
  /// folder it goes to are chosen in the same dialog, as an upload started
  /// away from a drive chooses them. The review that follows is the upload's
  /// own.
  Future<void> _chooseWhereToUpload(List<IOFile> files) async {
    final outer = widget.context;
    final sharingFileBloc = context.read<SharingFileBloc>();
    final syncCubit = context.read<SyncCubit>();
    final driveDao = context.read<DriveDao>();
    final drivesState = context.read<DrivesCubit>().state;
    // Owned drives, the last one used first, as Upload anywhere offers them;
    // before the drive list is known, all that this device holds.
    final drives = drivesState is DrivesLoadSuccess
        ? uploadDestinations(
            ownedDrives: drivesState.userDrives,
            lastSelectedDriveId: drivesState.selectedDriveId,
          )
        : await driveDao.allDrives().get();
    if (!outer.mounted) {
      sharingFileBloc.add(SharingFileCleared());
      return;
    }
    final strings = appLocalizationsOf(outer);
    // The share is spent however the picker closes: a choice has already
    // handed its files to the upload.
    await showDrivePicker(
      outer,
      title: strings.shareUploadTitle(files.length),
      purpose: DrivePickerPurpose.upload,
      drives: drives,
      showsPrivacy: true,
      noDrivesMessage: strings.noDrives,
      sync: (drive) => syncCubit.startSyncForDrive(driveId: drive.id),
      syncRefusal: () => syncCubit.lastSingleSyncRefusal,
      actionLabel: (_) => strings.uploadHere,
      onChoose: (choice) {
        if (!outer.mounted) return;
        promptToUpload(
          outer,
          drive: choice.drive,
          driveId: choice.drive.id,
          parentFolderId: choice.folder.id,
          isFolderUpload: false,
          files: files,
        );
      },
    ).whenComplete(() => sharingFileBloc.add(SharingFileCleared()));
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SharingFileBloc, SharingFileState>(
      listener: (context, state) {
        final syncCubit = context.read<SyncCubit>();
        final sharingFileBloc = context.read<SharingFileBloc>();
        if (state is SharingFileReceivedState) {
          // Uploading needs a wallet. A visitor who shares a file into the app
          // has nowhere to put it, so the share is dropped here rather than
          // walked into an upload dialog that cannot start.
          if (context.read<ProfileCubit>().state is! ProfileLoggedIn) {
            sharingFileBloc.add(SharingFileCleared());
            return;
          }

          if (syncCubit.state is SyncInProgress) {
            // Whatever the sync ends as, not `SyncIdle` specifically: a sync
            // that finished with one failed drive rests in
            // `SyncCompleteWithErrors`, which is not a `SyncIdle` and which
            // nothing clears - so this waited forever and the shared file was
            // dropped without a word.
            //
            // The subscription cancels itself once it has fired, rather than
            // outliving the share it was opened for.
            late final StreamSubscription<SyncState> subscription;
            subscription = syncCubit.stream.listen((syncState) {
              if (SyncCubit.syncHasFinished(syncState)) {
                subscription.cancel();
                context.read<SharingFileBloc>().add(ResubmitSharingFile());
              }
            });
            return;
          }

          _chooseWhereToUpload(state.files);
        }
      },
      child: widget.child,
    );
  }
}
