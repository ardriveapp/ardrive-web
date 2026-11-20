import 'package:ardrive/components/drive_picker/drive_picker_dialog.dart'
    show DrivePickerRow;
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
        ModalAction.dismiss(
          action: () => Navigator.of(context).pop(),
          title: appLocalizationsOf(context).cancel,
        ),
      ],
    );
  }
}

/// One drive, as the drive picker draws a drive: its row, with the word
/// public or private at the end, and under it a note when nothing on this
/// device has read the drive.
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
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final l10n = appLocalizationsOf(context);
    // The picker's own marks, so a drive looks the same in both.
    final icon = drive.privacy == DrivePrivacyTag.private
        ? ArDriveIcons.privateDrive(size: 20)
        : ArDriveIcons.publicDrive(size: 20);

    // The word as well as the icon: public or private is the choice being
    // made here, and it cannot be taken back.
    final row = DrivePickerRow(
      icon: icon,
      title: drive.name,
      trailing:
          drive.privacy == DrivePrivacyTag.private ? l10n.private : l10n.public,
      onTap: onTap,
    );

    if (!isUnsynced) return row;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        row,
        Padding(
          // Under the name: the row's inset and its icon and gap.
          padding: EdgeInsetsDirectional.only(
            start: ArDriveSpacing.xs + (icon.size ?? 24) + ArDriveSpacing.sm,
            bottom: ArDriveSpacing.xxs,
          ),
          child: Text(
            l10n.driveNeverSynced,
            style: typography.paragraphSmall(color: colorTokens.textLow),
          ),
        ),
      ],
    );
  }
}
