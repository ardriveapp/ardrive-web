import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Confirming the detach of a drive somebody else owns.
///
/// Every path here is gated on `!isOwner`, so this is always a shared drive,
/// and a shared drive detaches differently from one of your own. An owned
/// drive is found again by the next drive-list refresh, because it is
/// discovered from the transactions the wallet signed. A shared drive was
/// never discovered at all: it is here only because a link was followed, and
/// nothing will find it again. So detaching one is one-way unless the reader
/// still has that link, and the dialog gave them no way to know that.
///
/// That is the only thing worth adding. Somebody who attached a drive
/// belonging to somebody else does not need telling it stays on Arweave, and a
/// dialog that explains what a reader already knows buys nothing and costs
/// them the sentence that matters.
///
/// The sync line is said only while a sync is actually running, so the two are
/// not left looking like a race.
Future<void> showDetachDriveDialog({
  required BuildContext context,
  required DriveID driveID,
  required String driveName,
}) {
  // Read once, before the dialog opens. Inside it this is a static sentence
  // about what pressing Detach will do, not a live report - a line that
  // appeared or vanished under a reader deciding is worse than either.
  final syncCubit = context.read<SyncCubit>();
  final syncIsRunningOnIt = SyncCubit.syncTouchesDrive(
    state: syncCubit.state,
    syncingDriveId: syncCubit.syncingDriveId,
    completedDriveIds: syncCubit.completedDriveIds,
    runDriveIds: syncCubit.syncingDriveIds,
    driveId: driveID,
  );

  return showArDriveDialog(
    context,
    content: _DetachDriveModal(
      driveID: driveID,
      driveName: driveName,
      syncIsRunningOnIt: syncIsRunningOnIt,
    ),
  );
}

class _DetachDriveModal extends StatelessWidget {
  const _DetachDriveModal({
    required this.driveID,
    required this.driveName,
    required this.syncIsRunningOnIt,
  });

  final DriveID driveID;
  final String driveName;
  final bool syncIsRunningOnIt;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    Widget line(String text, {bool emphasised = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            text,
            style: typography.paragraphNormal(
              // The question carries the drive's name and reads a step
              // stronger than what follows it.
              color: emphasised ? colorTokens.textHigh : colorTokens.textMid,
              fontWeight:
                  emphasised ? ArFontWeight.semiBold : ArFontWeight.book,
            ),
          ),
        );

    return ArDriveStandardModalNew(
      title: appLocalizationsOf(context).detachDrive,
      // Everything in `content`, including the question. The modal renders
      // `description` only when it has no `content`, so passing both drops the
      // one carrying the drive's name - which is the single word a reader
      // needs to be sure they are detaching the drive they meant.
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          line(
            appLocalizationsOf(context).detachDriveQuestion(driveName),
            emphasised: true,
          ),
          line(appLocalizationsOf(context).detachDriveNeedsLinkAgain),
          if (syncIsRunningOnIt)
            line(appLocalizationsOf(context).detachDriveStopsSync),
        ],
      ),
      actions: [
        ModalAction(
          action: () => Navigator.of(context).pop(null),
          title: appLocalizationsOf(context).cancelEmphasized,
        ),
        ModalAction(
          action: () {
            context.read<DrivesCubit>().detachDrive(driveID);
            Navigator.of(context).pop();
          },
          title: appLocalizationsOf(context).detachEmphasized,
        ),
      ],
    );
  }
}
