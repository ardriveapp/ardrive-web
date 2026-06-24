import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive/turbo/topup/views/crypto_topup/amount_entry_view.dart';
import 'package:ardrive/turbo/topup/views/crypto_topup/ao_connect_signature_view.dart';
import 'package:ardrive/turbo/topup/views/crypto_topup/confirmation_view.dart';
import 'package:ardrive/turbo/topup/views/crypto_topup/error_view.dart';
import 'package:ardrive/turbo/topup/views/crypto_topup/network_switch_view.dart';
import 'package:ardrive/turbo/topup/views/crypto_topup/processing_view.dart';
import 'package:ardrive/turbo/topup/views/crypto_topup/success_view.dart';
import 'package:ardrive/turbo/topup/views/crypto_topup/token_selection_view.dart';
import 'package:ardrive/turbo/topup/views/crypto_topup/wallet_connection_view.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Main modal for crypto topup flow.
///
/// Orchestrates all views based on the current BLoC state.
class CryptoTopupModal extends StatelessWidget {
  final VoidCallback? onClose;

  const CryptoTopupModal({
    super.key,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return ArDriveModal(
      constraints: const BoxConstraints(
        maxWidth: 480,
        maxHeight: 680,
      ),
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        width: 480,
        child: BlocConsumer<CryptoTopupBloc, CryptoTopupState>(
          listener: _handleStateChanges,
          builder: (context, state) {
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _buildContent(context, state),
            );
          },
        ),
      ),
    );
  }

  void _handleStateChanges(BuildContext context, CryptoTopupState state) {
    // Handle account changed warning
    if (state is CryptoTopupAccountChangedWarning) {
      _showAccountChangedDialog(context, state);
    }

    // Handle price volatility warning
    if (state is CryptoTopupPriceVolatilityWarning) {
      _showPriceVolatilityDialog(context, state);
    }
  }

  Widget _buildContent(BuildContext context, CryptoTopupState state) {
    final bloc = context.read<CryptoTopupBloc>();

    if (state is CryptoTopupInitial) {
      // Start the flow
      bloc.add(const CryptoTopupStarted());
      return const Center(child: CircularProgressIndicator());
    }

    if (state is CryptoTopupTokenSelection) {
      return TokenSelectionView(
        key: const ValueKey('token_selection'),
        onClose: _close(context),
      );
    }

    if (state is CryptoTopupWalletConnection ||
        state is CryptoTopupWalletNotInstalled) {
      return WalletConnectionView(
        key: const ValueKey('wallet_connection'),
        onBack: () => bloc.add(const CryptoTopupGoBack()),
        onClose: _close(context),
      );
    }

    if (state is CryptoTopupAOConnectSignature) {
      return AOConnectSignatureView(
        key: const ValueKey('ao_connect_signature'),
        onBack: () => bloc.add(const CryptoTopupGoBack()),
        onClose: _close(context),
      );
    }

    if (state is CryptoTopupAmountEntry) {
      return AmountEntryView(
        key: const ValueKey('amount_entry'),
        onBack: () => bloc.add(const CryptoTopupGoBack()),
        onClose: _close(context),
      );
    }

    if (state is CryptoTopupConfirmation) {
      return ConfirmationView(
        key: const ValueKey('confirmation'),
        onBack: () => bloc.add(const CryptoTopupGoBack()),
        onClose: _close(context),
      );
    }

    if (state is CryptoTopupNetworkSwitch) {
      return NetworkSwitchView(
        key: const ValueKey('network_switch'),
        onBack: () => bloc.add(const CryptoTopupGoBack()),
        onClose: _close(context),
      );
    }

    if (state is CryptoTopupProcessing) {
      return const ProcessingView(
        key: ValueKey('processing'),
      );
    }

    if (state is CryptoTopupSuccess) {
      return SuccessView(
        key: const ValueKey('success'),
        onDone: _close(context),
      );
    }

    if (state is CryptoTopupError) {
      return ErrorView(
        key: const ValueKey('error'),
        onCancel: _close(context),
      );
    }

    if (state is CryptoTopupSessionTimeout) {
      return _SessionExpiredView(
        key: const ValueKey('session_expired'),
        onClose: _close(context),
      );
    }

    if (state is CryptoTopupConcurrentSessionWarning) {
      return _ConcurrentSessionView(
        key: const ValueKey('concurrent_session'),
        state: state,
        onClose: _close(context),
        onTakeOver: () => bloc.add(const CryptoTopupTakeOverSession()),
      );
    }

    // Default loading state - include close button as safety net
    return Stack(
      children: [
        const Center(child: CircularProgressIndicator()),
        Positioned(
          right: 20,
          top: 20,
          child: ArDriveClickArea(
            child: GestureDetector(
              onTap: _close(context),
              child: ArDriveIcons.x(),
            ),
          ),
        ),
      ],
    );
  }

  VoidCallback _close(BuildContext context) {
    return () {
      context.read<CryptoTopupBloc>().add(const CryptoTopupClose());
      onClose?.call();
      Navigator.of(context).pop();
    };
  }

  void _showAccountChangedDialog(
    BuildContext context,
    CryptoTopupAccountChangedWarning state,
  ) {
    final bloc = context.read<CryptoTopupBloc>();

    showArDriveDialog(
      context,
      content: ArDriveStandardModal(
        title: 'Wallet Account Changed',
        content: Text(
          'Your wallet account has changed to ${_truncateAddress(state.newAddress)}. '
          'Would you like to continue with this account?',
        ),
        actions: [
          ModalAction(
            action: () {
              Navigator.of(context).pop();
              bloc.add(const CryptoTopupCancelAccountChange());
            },
            title: 'Cancel',
          ),
          ModalAction(
            action: () {
              Navigator.of(context).pop();
              bloc.add(const CryptoTopupAcceptAccountChange());
            },
            title: 'Continue',
          ),
        ],
      ),
    );
  }

  void _showPriceVolatilityDialog(
    BuildContext context,
    CryptoTopupPriceVolatilityWarning state,
  ) {
    final bloc = context.read<CryptoTopupBloc>();
    final percentChange = state.percentChange.abs().toStringAsFixed(1);
    final direction = state.percentChange > 0 ? 'increased' : 'decreased';

    showArDriveDialog(
      context,
      content: ArDriveStandardModal(
        title: 'Price Changed',
        content: Text(
          'The price has $direction by $percentChange% since your last quote. '
          'Would you like to continue with the new price?',
        ),
        actions: [
          ModalAction(
            action: () {
              Navigator.of(context).pop();
              bloc.add(const CryptoTopupRejectNewQuote());
            },
            title: 'Cancel',
          ),
          ModalAction(
            action: () {
              Navigator.of(context).pop();
              bloc.add(const CryptoTopupAcceptNewQuote());
            },
            title: 'Accept',
          ),
        ],
      ),
    );
  }

  String _truncateAddress(String address) {
    if (address.length < 10) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }
}

/// Shows the crypto topup modal
Future<void> showCryptoTopupModal(BuildContext context) async {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      // The BLoC should be provided by the parent context
      return BlocProvider.value(
        value: context.read<CryptoTopupBloc>(),
        child: CryptoTopupModal(
          onClose: () {
            // Cleanup is handled by the bloc
          },
        ),
      );
    },
  );
}

/// Session expired view - renders inside the modal
/// Note: Does not include its own card/red line since it's inside ArDriveModal
class _SessionExpiredView extends StatelessWidget {
  final VoidCallback onClose;

  const _SessionExpiredView({
    super.key,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title - left aligned per modal design standard
        Text(
          'Session Expired',
          style: typography.heading5(
            fontWeight: ArFontWeight.bold,
            color: colors.themeFgDefault,
          ),
        ),
        const SizedBox(height: 24),
        // Icon and message
        Icon(
          Icons.timer_off_outlined,
          size: 64,
          color: colors.themeWarningFg,
        ),
        const SizedBox(height: 24),
        Text(
          'Your session has expired due to inactivity.',
          style: typography.paragraphLarge(
            color: colors.themeFgDefault,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Please start a new payment to continue.',
          style: typography.paragraphNormal(
            color: colors.themeFgMuted,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        // Close button
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ArDriveButton(
            text: 'Close',
            onPressed: onClose,
          ),
        ),
      ],
    );
  }
}

/// Concurrent session warning view - renders inside the modal
class _ConcurrentSessionView extends StatelessWidget {
  final CryptoTopupConcurrentSessionWarning state;
  final VoidCallback onClose;
  final VoidCallback onTakeOver;

  const _ConcurrentSessionView({
    super.key,
    required this.state,
    required this.onClose,
    required this.onTakeOver,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Stack(
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Red top line
            Container(
              height: 6,
              decoration: BoxDecoration(
                color: colorTokens.containerRed,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
            ),
            // Content
            Container(
              color: colors.themeBgCanvas,
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                  children: [
                    // Title
                    Text(
                      'Active Session Detected',
                      style: typography.heading5(
                        fontWeight: ArFontWeight.bold,
                        color: colors.themeFgDefault,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Icon and message
                    Icon(
                      Icons.tab_outlined,
                      size: 64,
                      color: colors.themeWarningFg,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Another payment session is active',
                      style: typography.paragraphLarge(
                        color: colors.themeFgDefault,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'A crypto payment is in progress in another tab. '
                      'You can take over this session or cancel.',
                      style: typography.paragraphNormal(
                        color: colors.themeFgMuted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: ArDriveButton(
                              text: 'Cancel',
                              style: ArDriveButtonStyle.secondary,
                              onPressed: onClose,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: ArDriveButton(
                              text: 'Take Over',
                              onPressed: onTakeOver,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
        // Close button in top right
        Positioned(
          right: 20,
          top: 20,
          child: ArDriveClickArea(
            child: GestureDetector(
              onTap: onClose,
              child: ArDriveIcons.x(),
            ),
          ),
        ),
      ],
    );
  }
}
