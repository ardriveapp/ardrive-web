import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive/turbo/topup/components/turbo_topup_scaffold.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

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
          ModalAction.dismiss(
              title: appLocalizationsOf(context).close, action: onClose!),
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
CryptoNotice? cryptoNoticeFor(
    CryptoTopupState state, AppLocalizations strings) {
  if (state is CryptoTopupAccountChangedWarning) {
    return CryptoNotice(
      key: 'account_changed',
      title: strings.cryptoAccountChangedTitle,
      message: strings.cryptoAccountChangedMessage,
      actionTitle: strings.cryptoStartAgain,
      action: const CryptoTopupRetry(),
    );
  }
  if (state is CryptoTopupSessionTimeout) {
    return CryptoNotice(
      key: 'session_timeout',
      title: strings.cryptoSessionTimedOutTitle,
      message: strings.cryptoSessionTimedOutMessage,
      actionTitle: strings.cryptoStartAgain,
      action: const CryptoTopupRetry(),
    );
  }
  if (state is CryptoTopupConcurrentSessionWarning && state.otherTabPaying) {
    return CryptoNotice(
      key: 'concurrent_session_paying',
      title: strings.cryptoPayingInOtherTabTitle,
      message: strings.cryptoPayingInOtherTabMessage,
      actionTitle: strings.checkAgain,
      action: const CryptoTopupTakeOverSession(),
    );
  }
  if (state is CryptoTopupConcurrentSessionWarning) {
    return CryptoNotice(
      key: 'concurrent_session',
      title: strings.cryptoOtherTabTitle,
      message: strings.cryptoOtherTabMessage,
      actionTitle: strings.cryptoUseThisTab,
      action: const CryptoTopupTakeOverSession(),
    );
  }
  if (state is CryptoTopupPriceVolatilityWarning) {
    return CryptoNotice(
      key: 'price_volatility',
      title: strings.cryptoPriceChangedTitle,
      message: strings.cryptoPriceChangedMessage(
          state.percentChange.abs().toStringAsFixed(1)),
      actionTitle: strings.continueEmphasized,
      action: const CryptoTopupPriceVolatilityAccepted(),
      closeEvent: const CryptoTopupPriceVolatilityRejected(),
    );
  }
  return null;
}
