import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// An error, on the standard dialog: its title, what happened, and Close.
/// With [showShareLogsButton], Copy logs too, for sending to support.
///
/// It was a sign-in style card with a centred heading, an alert icon and
/// full-width buttons, unlike every other dialog, and it is also shown when
/// a drive can't be created. Completes when the dialog is closed.
Future<void> showErrorDialog(
    {required BuildContext context,
    String? title,
    required String message,
    bool showShareLogsButton = false}) {
  return showArDriveDialog(
    context,
    barrierDismissible: false,
    useRootNavigator: false,
    content: _ErrorDialog(
      title: title ?? appLocalizationsOf(context).error,
      message: message,
      showShareLogsButton: showShareLogsButton,
    ),
  );
}

class _ErrorDialog extends StatefulWidget {
  const _ErrorDialog({
    required this.title,
    required this.message,
    required this.showShareLogsButton,
  });

  final String title;
  final String message;
  final bool showShareLogsButton;

  @override
  State<_ErrorDialog> createState() => _ErrorDialogState();
}

class _ErrorDialogState extends State<_ErrorDialog> {
  /// The last Copy logs: null before one, true when it copied, false when
  /// the browser refused the clipboard. The button says which, and stays
  /// there to try again.
  bool? _copied;

  @override
  Widget build(BuildContext context) {
    final l10n = appLocalizationsOf(context);
    return ArDriveStandardModalNew(
      title: widget.title,
      description: widget.message,
      // A long message scrolls, and Close stays in reach.
      scrollableContent: true,
      // The X is read in the dialog's language, like its Close.
      closeLabel: l10n.close,
      actions: [
        ModalAction.close(
          action: () => Navigator.pop(context),
          title: l10n.close,
        ),
        if (widget.showShareLogsButton)
          ModalAction(
            title: switch (_copied) {
              true => l10n.copied,
              false => l10n.couldNotCopy,
              null => l10n.copyLogs,
            },
            action: () async {
              try {
                final logs = await logger.getLogs();
                await Clipboard.setData(ClipboardData(text: logs));
                if (mounted) setState(() => _copied = true);
              } catch (_) {
                if (mounted) setState(() => _copied = false);
              }
            },
          ),
      ],
    );
  }
}
