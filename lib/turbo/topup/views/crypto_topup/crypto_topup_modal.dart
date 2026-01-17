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
      content: SizedBox(
        width: 480,
        height: 600,
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
    // Handle session timeout
    if (state is CryptoTopupSessionTimeout) {
      _showSessionTimeoutDialog(context);
    }

    // Handle account changed warning
    if (state is CryptoTopupAccountChangedWarning) {
      _showAccountChangedDialog(context, state);
    }

    // Handle concurrent session warning
    if (state is CryptoTopupConcurrentSessionWarning) {
      _showConcurrentSessionDialog(context, state);
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

    // Default loading state
    return const Center(child: CircularProgressIndicator());
  }

  VoidCallback _close(BuildContext context) {
    return () {
      context.read<CryptoTopupBloc>().add(const CryptoTopupClose());
      onClose?.call();
      Navigator.of(context).pop();
    };
  }

  void _showSessionTimeoutDialog(BuildContext context) {
    showArDriveDialog(
      context,
      content: ArDriveStandardModal(
        title: 'Session Expired',
        content: const Text(
          'Your session has expired due to inactivity. Please start a new payment.',
        ),
        actions: [
          ModalAction(
            action: () {
              Navigator.of(context).pop(); // Close dialog
              _close(context)(); // Close modal
            },
            title: 'Close',
          ),
        ],
      ),
    );
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

  void _showConcurrentSessionDialog(
    BuildContext context,
    CryptoTopupConcurrentSessionWarning state,
  ) {
    final bloc = context.read<CryptoTopupBloc>();

    showArDriveDialog(
      context,
      content: ArDriveStandardModal(
        title: 'Active Session Detected',
        content: const Text(
          'Another crypto payment session is active in a different tab. '
          'Would you like to take over this session?',
        ),
        actions: [
          ModalAction(
            action: () {
              Navigator.of(context).pop();
              _close(context)();
            },
            title: 'Cancel',
          ),
          ModalAction(
            action: () {
              Navigator.of(context).pop();
              bloc.add(const CryptoTopupTakeOverSession());
            },
            title: 'Take Over',
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
