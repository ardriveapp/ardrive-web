import 'package:ardrive/turbo/topup/components/turbo_topup_scaffold.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// A crypto top-up screen that stops the flow with a message and a way out:
/// the wallet switched accounts, the session ran out, another tab holds the
/// session, or the price moved.
///
/// Nothing has been paid when these show, so they can always be closed.
class CryptoNoticeView extends StatelessWidget {
  const CryptoNoticeView({
    super.key,
    required this.title,
    required this.message,
    required this.actionTitle,
    required this.onAction,
    required this.onClose,
    this.type = ArDriveNoticeType.warning,
  });

  final String title;
  final String message;

  /// The primary action, for example Start again.
  final String actionTitle;
  final VoidCallback onAction;
  final VoidCallback? onClose;
  final ArDriveNoticeType type;

  @override
  Widget build(BuildContext context) {
    return TurboTopupScaffold(
      title: title,
      canClose: onClose != null,
      onClose: onClose,
      actions: [
        if (onClose != null)
          ModalAction.dismiss(title: 'Close', action: onClose!),
        ModalAction(title: actionTitle, action: onAction),
      ],
      child: ArDriveNotice(type: type, message: message),
    );
  }
}
