import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// Which drives a full resync would run over, so the confirmation can name
/// them.
class FullResyncScope {
  const FullResyncScope.allDrives()
      : driveName = null,
        selectedCount = null,
        unreadCount = null;

  const FullResyncScope.drive(String this.driveName)
      : selectedCount = null,
        unreadCount = null;

  const FullResyncScope.selected(int this.selectedCount)
      : driveName = null,
        unreadCount = null;

  /// The drives a sync could not read every item of, for its Try again.
  const FullResyncScope.unread(int this.unreadCount)
      : driveName = null,
        selectedCount = null;

  final String? driveName;
  final int? selectedCount;
  final int? unreadCount;
}

/// Asks before a full resync starts, and returns whether the user agreed.
///
/// A full resync rereads every block of a drive's history without snapshots,
/// so on a large drive it runs far longer than a sync, and the menus give it
/// one line. This says what it does, that it is slow, and that it deletes
/// nothing, which is the first worry of anyone reaching for it because
/// something looks missing.
Future<bool> confirmFullResync(
  BuildContext context,
  FullResyncScope scope,
) async {
  var confirmed = false;
  await showArDriveDialog(
    context,
    content: _FullResyncModal(
      scope: scope,
      onConfirm: () => confirmed = true,
    ),
  );
  return confirmed;
}

class _FullResyncModal extends StatelessWidget {
  const _FullResyncModal({required this.scope, required this.onConfirm});

  final FullResyncScope scope;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final localizations = appLocalizationsOf(context);

    final body = scope.driveName != null
        ? localizations.fullResyncConfirmDrive(scope.driveName!)
        : scope.unreadCount != null
            ? localizations.fullResyncConfirmUnreadDrives(scope.unreadCount!)
            : scope.selectedCount != null
                ? localizations.fullResyncConfirmSelectedDrives(
                    scope.selectedCount!,
                  )
                : localizations.fullResyncConfirmAllDrives;

    return ArDriveStandardModalNew(
      title: localizations.fullResyncConfirmTitle,
      hasCloseButton: true,
      closeLabel: localizations.close,
      content: Text(
        body,
        style: typography.paragraphNormal(color: colorTokens.textMid),
      ),
      actions: [
        ModalAction(
          action: () => Navigator.of(context).pop(),
          title: localizations.cancelEmphasized,
        ),
        ModalAction(
          action: () {
            onConfirm();
            Navigator.of(context).pop();
          },
          title: localizations.fullResyncConfirmAction,
        ),
      ],
    );
  }
}
