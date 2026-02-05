import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// AO Connect Signature view - one-time signature to enable Ethereum wallet
/// to interact with AO network for ARIO payments.
///
/// This signature:
/// - Proves wallet ownership
/// - Enables InjectedEthereumSigner to derive public key via ecrecover
/// - Is cached for the session (not persisted)
class AOConnectSignatureView extends StatelessWidget {
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  const AOConnectSignatureView({
    super.key,
    this.onBack,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CryptoTopupBloc, CryptoTopupState>(
      buildWhen: (previous, current) =>
          previous is CryptoTopupAOConnectSignature ||
          current is CryptoTopupAOConnectSignature,
      builder: (context, state) {
        if (state is! CryptoTopupAOConnectSignature) {
          return const SizedBox.shrink();
        }

        return _AOConnectSignatureContent(
          state: state,
          onBack: onBack,
          onClose: onClose,
        );
      },
    );
  }
}

class _AOConnectSignatureContent extends StatelessWidget {
  final CryptoTopupAOConnectSignature state;
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  const _AOConnectSignatureContent({
    required this.state,
    this.onBack,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final bloc = context.read<CryptoTopupBloc>();

    // Show signing state
    if (state.isSigningMessage) {
      return _SigningInProgress(onClose: onClose);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with back button
          Row(
            children: [
              if (onBack != null)
                GestureDetector(
                  onTap: onBack,
                  child: Icon(
                    Icons.arrow_back,
                    color: colorTokens.textMid,
                    size: 24,
                  ),
                ),
              if (onBack != null) const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Connect to AO Network',
                  style: typography.heading4(
                    fontWeight: ArFontWeight.bold,
                    color: colorTokens.textHigh,
                  ),
                ),
              ),
              if (onClose != null)
                GestureDetector(
                  onTap: onClose,
                  child: Icon(
                    Icons.close,
                    color: colorTokens.textMid,
                    size: 24,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Description
          Text(
            'To pay with ARIO on AO using your Ethereum wallet, we need to establish a secure connection.',
            style: typography.paragraphNormal(
              color: colorTokens.textMid,
            ),
          ),
          const SizedBox(height: 24),

          // Info card
          _InfoCard(ethAddress: state.ethAddress),
          const SizedBox(height: 24),

          // Error message
          if (state.error != null) ...[
            _ErrorMessage(
              message: state.error!,
              isUserRejected: state.isUserRejected,
            ),
            const SizedBox(height: 16),
          ],

          // Connected wallet info
          _ConnectedWalletCard(address: state.ethAddress),
          const SizedBox(height: 32),

          // Action buttons
          Row(
            children: [
              if (onBack != null)
                Expanded(
                  child: ArDriveButton(
                    text: 'Back',
                    style: ArDriveButtonStyle.secondary,
                    onPressed: onBack,
                  ),
                ),
              if (onBack != null) const SizedBox(width: 12),
              Expanded(
                child: ArDriveButton(
                  text: state.error != null ? 'Try Again' : 'Sign & Connect',
                  onPressed: () {
                    bloc.add(const CryptoTopupAOConnectSignatureRequested());
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SigningInProgress extends StatelessWidget {
  final VoidCallback? onClose;

  const _SigningInProgress({this.onClose});

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Text(
                  'Connect to AO Network',
                  style: typography.heading4(
                    fontWeight: ArFontWeight.bold,
                    color: colorTokens.textHigh,
                  ),
                ),
              ),
              if (onClose != null)
                GestureDetector(
                  onTap: onClose,
                  child: Icon(
                    Icons.close,
                    color: colorTokens.textMid,
                    size: 24,
                  ),
                ),
            ],
          ),
          const Spacer(),
          // Spinner
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: colorTokens.textHigh,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Waiting for signature...',
            style: typography.heading5(
              fontWeight: ArFontWeight.semiBold,
              color: colorTokens.textHigh,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Please sign the message in your wallet.',
            style: typography.paragraphNormal(
              color: colorTokens.textMid,
            ),
            textAlign: TextAlign.center,
          ),
          const Spacer(),
          // Cancel button
          SizedBox(
            width: double.infinity,
            child: ArDriveButton(
              text: 'Cancel',
              style: ArDriveButtonStyle.secondary,
              onPressed: onClose,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String ethAddress;

  const _InfoCard({required this.ethAddress});

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorTokens.containerL1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorTokens.strokeLow),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This requires a one-time signature (no transaction or gas fee). This signature:',
            style: typography.paragraphNormal(
              color: colorTokens.textMid,
            ),
          ),
          const SizedBox(height: 12),
          const _InfoItem(
            icon: Icons.verified_user,
            text: 'Proves you own this wallet',
          ),
          const SizedBox(height: 8),
          const _InfoItem(
            icon: Icons.hub,
            text: 'Enables interaction with the AO network',
          ),
          const SizedBox(height: 8),
          const _InfoItem(
            icon: Icons.cached,
            text: "Is cached for your session (won't ask again)",
          ),
        ],
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoItem({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: colorTokens.textMid,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: typography.paragraphSmall(
              color: colorTokens.textHigh,
            ),
          ),
        ),
      ],
    );
  }
}

class _ConnectedWalletCard extends StatelessWidget {
  final String address;

  const _ConnectedWalletCard({required this.address});

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorTokens.containerL1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorTokens.strokeLow),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colorTokens.containerL2,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              Icons.account_balance_wallet,
              color: colorTokens.textMid,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Connected Wallet',
                  style: typography.paragraphSmall(
                    color: colorTokens.textMid,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _truncateAddress(address),
                  style: typography.paragraphNormal(
                    fontWeight: ArFontWeight.semiBold,
                    color: colorTokens.textHigh,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: colorTokens.textHigh,
              shape: BoxShape.circle,
            ),
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

class _ErrorMessage extends StatelessWidget {
  final String message;
  final bool isUserRejected;

  const _ErrorMessage({
    required this.message,
    this.isUserRejected = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorTokens.containerL1,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorTokens.strokeLow),
      ),
      child: Row(
        children: [
          Icon(
            isUserRejected ? Icons.block : Icons.error_outline,
            color: colorTokens.textLow,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isUserRejected ? 'Signature Rejected' : 'Error',
                  style: typography.paragraphSmall(
                    fontWeight: ArFontWeight.semiBold,
                    color: colorTokens.textHigh,
                  ),
                ),
                Text(
                  isUserRejected
                      ? 'You rejected the signature request. This signature is required to proceed.'
                      : message,
                  style: typography.paragraphSmall(
                    color: colorTokens.textMid,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
