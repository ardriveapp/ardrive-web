import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/drive_create/first_drive.dart';
import 'package:ardrive/components/progress_dialog.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart'
    show DrivePrivacy;
import 'package:ardrive/locked_drives/domain/drive_unlocker.dart';
import 'package:ardrive/locked_drives/presentation/set_drive_password_dialog.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/upload_entry/domain/upload_request.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// How the first upload's drive came out.
enum FirstUploadDrive {
  /// "My files" was made, and selected, which carries the upload into it.
  made,

  /// The person cancelled setting their drive password. Nothing was made.
  cancelled,

  /// The account has private drives this session hasn't opened, so its
  /// drive password is checked on one of them: Create drive does that.
  needsDrivePasswordChecked,

  /// Making it failed. Nothing is left behind.
  failed,
}

/// The one place the first upload of an account with no drive is decided:
/// it goes into a private "My files", made here, never a public drive
/// (Arweave is permanent).
///
/// - An account with a drive password this session (a keyfile, phrase or
///   generated account's sign-in password, or one set or checked earlier)
///   gets "My files" with it, and is asked nothing.
/// - An account that signed in with a browser wallet and has no drive
///   password yet is asked to set one ([askNewDrivePassword], "Keep your
///   files private"). Cancel makes nothing.
///
/// [cubit] is a private [DriveCreateCubit]; this closes it.
Future<FirstUploadDrive> makeFirstPrivateDrive({
  required DriveCreateCubit cubit,
  required Future<String?> Function() askNewDrivePassword,
  VoidCallback? onCreating,
}) async {
  try {
    String? newDrivePassword;
    // Checked on Arweave first: a password is never set over private
    // drives the local list doesn't show yet.
    switch (await cubit.confirmDrivePasswordAsk()) {
      case DrivePasswordAsk.set:
        newDrivePassword = await askNewDrivePassword();
        if (newDrivePassword == null) return FirstUploadDrive.cancelled;
      case DrivePasswordAsk.enter:
        return FirstUploadDrive.needsDrivePasswordChecked;
      case null:
        break;
    }

    onCreating?.call();
    await cubit.submit(firstDriveName, newDrivePassword: newDrivePassword);
    return cubit.state is DriveCreateSuccess
        ? FirstUploadDrive.made
        : FirstUploadDrive.failed;
  } catch (e, stackTrace) {
    logger.e('Could not make My files for the first upload', e, stackTrace);
    return FirstUploadDrive.failed;
  } finally {
    await cubit.close();
  }
}

/// The cubit that makes the first upload's drive: always private, never a
/// public drive by default (Arweave is permanent).
DriveCreateCubit firstDriveCubit({
  required ArweaveService arweave,
  required TurboUploadService turboUploadService,
  required DriveDao driveDao,
  required ProfileCubit profileCubit,
  required DrivesCubit drivesCubit,
  required DriveUnlocker driveUnlocker,
}) =>
    DriveCreateCubit(
      privacy: DrivePrivacy.private,
      arweave: arweave,
      turboUploadService: turboUploadService,
      driveDao: driveDao,
      profileCubit: profileCubit,
      drivesCubit: drivesCubit,
      driveUnlocker: driveUnlocker,
    );

/// Upload pressed with no drive at all (Getting started's "Upload your first
/// files", or Upload anywhere else): makes "My files" and carries the upload
/// into it, through the same waiting upload a drive chosen from a list uses.
/// [openCreateDrive] is Create drive, for an account whose drive password
/// must first be checked on a drive it has.
Future<void> uploadIntoFirstDrive(
  BuildContext context, {
  required AppRouterDelegate router,
  required DrivesCubit drivesCubit,
  required bool isFolderUpload,
  required Future<void> Function() openCreateDrive,
  @visibleForTesting DriveCreateCubit Function()? newCubit,
  @visibleForTesting Future<String?> Function()? askNewDrivePassword,
}) async {
  final profile = context.read<ProfileCubit>().state;
  if (profile is! ProfileLoggedIn) return;

  final cubit = newCubit?.call() ??
      firstDriveCubit(
        arweave: context.read<ArweaveService>(),
        turboUploadService: context.read<TurboUploadService>(),
        driveDao: context.read<DriveDao>(),
        profileCubit: context.read<ProfileCubit>(),
        drivesCubit: drivesCubit,
        driveUnlocker: context.read<DriveUnlocker>(),
      );

  // Creating the drive selects it, and the selection opens it with the
  // upload waiting, as any first drive's does.
  final selection = drivesCubit.driveSelections.take(1).listen((driveId) {
    router.requestUpload(
      UploadRequest(driveId: driveId, isFolderUpload: isFolderUpload),
    );
  });

  var progressShown = false;
  final navigator = Navigator.of(context, rootNavigator: true);

  try {
    final outcome = await makeFirstPrivateDrive(
      cubit: cubit,
      askNewDrivePassword: askNewDrivePassword ??
          () => showSetDrivePasswordDialog(
                context,
                walletAddress: profile.user.walletAddress,
              ),
      onCreating: () {
        if (!context.mounted) return;
        progressShown = true;
        unawaited(showArDriveDialog(
          context,
          barrierDismissible: false,
          content: ProgressDialog(
            title: appLocalizationsOf(context).firstDriveSettingUp,
          ),
        ));
      },
    );

    if (progressShown) navigator.pop();

    switch (outcome) {
      case FirstUploadDrive.made:
      case FirstUploadDrive.cancelled:
        break;
      case FirstUploadDrive.needsDrivePasswordChecked:
        await selection.cancel();
        if (context.mounted) await openCreateDrive();
      case FirstUploadDrive.failed:
        if (context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
            content: Text(appLocalizationsOf(context).firstDriveFailed),
          ));
        }
    }
  } finally {
    await selection.cancel();
  }
}
