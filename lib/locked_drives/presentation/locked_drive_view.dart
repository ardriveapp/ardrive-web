import 'package:ardrive/components/drive_fingerprint.dart';
import 'package:ardrive/locked_drives/domain/drive_unlock_session.dart';
import 'package:ardrive/locked_drives/domain/locked_drive.dart';
import 'package:ardrive/locked_drives/presentation/unlock_drive_dialog.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// A locked drive's page: "This drive is locked", and Unlock.
///
/// Drawn where the explorer would otherwise have nothing to show for a drive
/// it has no row for. While [driveId] is not locked - it was never this
/// user's, or it has just been unlocked and the explorer is about to open it -
/// this draws [otherwise].
class LockedDriveView extends StatelessWidget {
  const LockedDriveView({
    super.key,
    required this.driveId,
    required this.otherwise,
    this.frame,
  });

  final String driveId;
  final Widget otherwise;

  /// Puts the page's chrome around the panel. Only ever called for a drive
  /// that is locked, so [otherwise] is drawn bare.
  final Widget Function(Widget panel)? frame;

  @override
  Widget build(BuildContext context) {
    final session = context.read<DriveUnlockSession>();

    return StreamBuilder<List<LockedDrive>>(
      stream: session.lockedDrives,
      initialData: session.currentLockedDrives,
      builder: (context, _) {
        if (!session.isLocked(driveId)) {
          return otherwise;
        }

        final panel = LockedDrivePanel(
          driveId: driveId,
          onUnlock: () => showUnlockDriveDialog(context, driveId: driveId),
        );

        return frame?.call(panel) ?? panel;
      },
    );
  }
}

/// The panel itself, with nothing to look up, so it can be drawn in a test.
class LockedDrivePanel extends StatelessWidget {
  const LockedDrivePanel({
    super.key,
    required this.driveId,
    required this.onUnlock,
  });

  final String driveId;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);

    return ArDriveEmptyState(
      key: const Key('lockedDrivePanel'),
      icon: DriveFingerprint(driveId: driveId, size: 40),
      title: strings.driveIsLocked,
      actionLabel: strings.unlock,
      onAction: onUnlock,
    );
  }
}
