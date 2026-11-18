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
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final l10n = appLocalizationsOf(context);
    return ArDriveStandardModalNew(
      title: widget.title,
      description: widget.message,
      actions: [
        ModalAction.close(
          action: () => Navigator.pop(context),
          title: l10n.close,
        ),
        if (widget.showShareLogsButton)
          ModalAction(
            title: _copied ? l10n.copied : l10n.copyLogs,
            action: () async {
              final logs = await logger.getLogs();
              await Clipboard.setData(ClipboardData(text: logs));
              if (mounted) setState(() => _copied = true);
            },
          ),
      ],
    );
  }
}
