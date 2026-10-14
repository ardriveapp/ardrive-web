import 'package:ardrive/models/models.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/material.dart';

/// Which drive an upload started away from any drive goes to.
///
/// Only shown when there is more than one choice: with one drive, opening it
/// is the whole decision. The list arrives already ordered, last-used first.
class UploadDestinationDialog extends StatelessWidget {
  const UploadDestinationDialog({
    super.key,
    required this.drives,
    required this.unsyncedDriveIds,
    required this.onSelect,
  });

  final List<Drive> drives;

  /// Drives nothing on this device has read. Still offered: choosing one
  /// leads to its sync. Marked so the extra step is not a surprise.
  final Set<String> unsyncedDriveIds;

  /// Called after this dialog has closed.
  final void Function(Drive drive) onSelect;

  @override
  Widget build(BuildContext context) {
    return ArDriveStandardModalNew(
      title: appLocalizationsOf(context).uploadWhichDrive,
      // Bounded to the viewport and scrolled when it will not fit, so the
      // Cancel button cannot be pushed off a short screen - which is what a
      // phone at twice the text size is.
      scrollableContent: true,
      content: SizedBox(
        width: kMediumDialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final drive in drives)
              _DestinationRow(
                drive: drive,
                isUnsynced: unsyncedDriveIds.contains(drive.id),
                onTap: () {
                  Navigator.of(context).pop();
                  onSelect(drive);
                },
              ),
          ],
        ),
      ),
      actions: [
        ModalAction(
          action: () => Navigator.of(context).pop(),
          title: appLocalizationsOf(context).cancel,
        ),
      ],
    );
  }
}

class _DestinationRow extends StatelessWidget {
  const _DestinationRow({
    required this.drive,
    required this.isUnsynced,
    required this.onTap,
  });

  final Drive drive;
  final bool isUnsynced;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final theme = ArDriveTheme.of(context).themeData;
    final colorTokens = theme.colorTokens;
    final isPrivate = drive.privacy == DrivePrivacyTag.private;
    final l10n = appLocalizationsOf(context);

    final highlight = theme.dropdownTheme.hoverColor;

    // A button in every sense, not only to a pointer: reachable with Tab,
    // chosen with Enter or Space, and announced as a button with its drive's
    // name. A bare gesture detector did none of that, so choosing a drive,
    // and with it finishing an upload, needed a mouse.
    return Semantics(
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          hoverColor: highlight,
          focusColor: highlight,
          highlightColor: highlight,
          splashFactory: NoSplash.splashFactory,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: [
                isPrivate
                    ? ArDriveIcons.privateDrive(
                        size: 18,
                        color: colorTokens.textMid,
                      )
                    : ArDriveIcons.publicDrive(
                        size: 18,
                        color: colorTokens.textMid,
                      ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        drive.name,
                        overflow: TextOverflow.ellipsis,
                        style: typography.paragraphLarge(
                          color: colorTokens.textHigh,
                          fontWeight: ArFontWeight.semiBold,
                        ),
                      ),
                      if (isUnsynced)
                        Text(
                          l10n.driveNeverSynced,
                          style: typography.paragraphSmall(
                            color: colorTokens.textLow,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // The word as well as the icon: public or private is the
                // choice being made here, and it cannot be taken back.
                Text(
                  isPrivate ? l10n.private : l10n.public,
                  style: typography.paragraphNormal(
                    color: colorTokens.textMid,
                    fontWeight: ArFontWeight.semiBold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What Upload says to somebody with no drive to upload to.
///
/// Explains the one thing they need to know, that files live in drives, and
/// offers the step that fixes it. The upload carries on once the drive exists.
class UploadNeedsDriveDialog extends StatelessWidget {
  const UploadNeedsDriveDialog({super.key, required this.onCreateDrive});

  /// Called after this dialog has closed.
  final VoidCallback onCreateDrive;

  @override
  Widget build(BuildContext context) {
    final l10n = appLocalizationsOf(context);

    return ArDriveStandardModalNew(
      title: l10n.uploadNeedsDriveTitle,
      description: l10n.uploadNeedsDriveDescription,
      scrollableContent: true,
      actions: [
        ModalAction(
          action: () => Navigator.of(context).pop(),
          title: l10n.cancel,
        ),
        ModalAction(
          action: () {
            Navigator.of(context).pop();
            onCreateDrive();
          },
          title: l10n.newDrive,
          customWidth: 120,
        ),
      ],
    );
  }
}
