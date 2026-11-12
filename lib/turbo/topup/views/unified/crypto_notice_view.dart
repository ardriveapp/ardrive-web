import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
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

/// What a warning state says and what its two buttons do.
///
/// Kept apart from the widgets so the mapping from a state to its events can
/// be tested on its own: swapping one event for another changes what the
/// person's money or session does.
class CryptoNotice {
  const CryptoNotice({
    required this.key,
    required this.title,
    required this.message,
    required this.actionTitle,
    required this.action,
    this.closeEvent,
  });

  final String key;
  final String title;
  final String message;
  final String actionTitle;

  /// Sent by the primary button.
  final CryptoTopupEvent action;

  /// Sent by Close, or null to close the dialog without telling the bloc.
  final CryptoTopupEvent? closeEvent;
}

/// The notice for [state], or null when [state] is not a stopping warning.
CryptoNotice? cryptoNoticeFor(CryptoTopupState state) {
  if (state is CryptoTopupAccountChangedWarning) {
    return const CryptoNotice(
      key: 'account_changed',
      title: 'Account changed',
      message: 'Your wallet switched accounts. Start again with the account '
          'you want to pay from.',
      actionTitle: 'Start again',
      action: CryptoTopupRetry(),
    );
  }
  if (state is CryptoTopupSessionTimeout) {
    return const CryptoNotice(
      key: 'session_timeout',
      title: 'Session timed out',
      message: 'This top-up took too long. Start again.',
      actionTitle: 'Start again',
      action: CryptoTopupRetry(),
    );
  }
  if (state is CryptoTopupConcurrentSessionWarning) {
    return const CryptoNotice(
      key: 'concurrent_session',
      title: 'Top-up open in another tab',
      message: 'Another tab is topping up. Use this tab instead, or close.',
      actionTitle: 'Use this tab',
      action: CryptoTopupTakeOverSession(),
    );
  }
  if (state is CryptoTopupPriceVolatilityWarning) {
    return CryptoNotice(
      key: 'price_volatility',
      title: 'Price changed',
      message: 'The credits you get changed by '
          '${state.percentChange.abs().toStringAsFixed(1)}%. Continue at the '
          'new price, or go back.',
      actionTitle: 'Continue',
      action: const CryptoTopupPriceVolatilityAccepted(),
      closeEvent: const CryptoTopupPriceVolatilityRejected(),
    );
  }
  return null;
}
