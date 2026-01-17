import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/views/crypto_topup/components/components.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

/// Wallet connection view - prompts user to connect appropriate wallet.
class WalletConnectionView extends StatelessWidget {
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  const WalletConnectionView({
    super.key,
    this.onBack,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CryptoTopupBloc, CryptoTopupState>(
      buildWhen: (previous, current) =>
          current is CryptoTopupWalletConnection ||
          current is CryptoTopupWalletNotInstalled,
      builder: (context, state) {
        if (state is CryptoTopupWalletConnection) {
          return _WalletConnectionContent(
            state: state,
            onBack: onBack,
            onClose: onClose,
          );
        }

        if (state is CryptoTopupWalletNotInstalled) {
          return _WalletNotInstalledContent(
            state: state,
            onBack: onBack,
            onClose: onClose,
          );
        }

        return const SizedBox.shrink();
      },
    );
  }
}

class _WalletConnectionContent extends StatelessWidget {
  final CryptoTopupWalletConnection state;
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  const _WalletConnectionContent({
    required this.state,
    this.onBack,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final bloc = context.read<CryptoTopupBloc>();

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
                  'Connect Wallet',
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
          const SizedBox(height: 8),
          Text(
            'Connect a ${_getWalletTypeDescription(state.token)} wallet to continue.',
            style: typography.paragraphNormal(
              color: colorTokens.textMid,
            ),
          ),
          const SizedBox(height: 24),

          // Selected token info
          _SelectedTokenInfo(token: state.token),
          const SizedBox(height: 24),

          // Network switching indicator
          if (state.isSwitchingNetwork) ...[
            _NetworkSwitchingIndicator(token: state.token),
            const SizedBox(height: 16),
          ],

          // Error message
          if (state.error != null && !state.isSwitchingNetwork) ...[
            _ErrorMessage(
              message: state.error!,
              isUserRejected: state.isUserRejected,
            ),
            const SizedBox(height: 16),
          ],

          // Wallet options (hide while switching network)
          if (!state.isSwitchingNetwork)
            _WalletOptions(
            token: state.token,
            walletType: state.walletType,
            isConnecting: state.isConnecting,
            onConnect: (UIWalletProvider provider) {
              bloc.add(CryptoTopupConnectWallet(
                ethereumProvider: provider.ethereumProvider,
                solanaProvider: provider.solanaProvider,
              ));
            },
          ),
        ],
      ),
    );
  }

  String _getWalletTypeDescription(CryptoToken token) {
    switch (token.blockchain) {
      case Blockchain.ethereum:
      case Blockchain.base:
        return 'Ethereum';
      case Blockchain.solana:
        return 'Solana';
      case Blockchain.ao:
        return 'Arweave';
    }
  }
}

class _SelectedTokenInfo extends StatelessWidget {
  final CryptoToken token;

  const _SelectedTokenInfo({required this.token});

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
          // Token icon placeholder
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colorTokens.containerL2,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Center(
              child: Text(
                token.symbol.substring(0, token.symbol.length > 2 ? 2 : token.symbol.length),
                style: typography.paragraphSmall(
                  fontWeight: ArFontWeight.bold,
                  color: colorTokens.textHigh,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Paying with ${token.displayName}',
                style: typography.paragraphNormal(
                  fontWeight: ArFontWeight.semiBold,
                  color: colorTokens.textHigh,
                ),
              ),
              Text(
                'on ${token.networkDisplayName}',
                style: typography.paragraphSmall(
                  color: colorTokens.textMid,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WalletOptions extends StatefulWidget {
  final CryptoToken token;
  final WalletType walletType;
  final bool isConnecting;
  final void Function(UIWalletProvider provider) onConnect;

  const _WalletOptions({
    required this.token,
    required this.walletType,
    required this.isConnecting,
    required this.onConnect,
  });

  @override
  State<_WalletOptions> createState() => _WalletOptionsState();
}

class _WalletOptionsState extends State<_WalletOptions> {
  UIWalletProvider? _selectedProvider;

  @override
  void didUpdateWidget(_WalletOptions oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Clear selection when connection attempt finishes
    if (!widget.isConnecting && oldWidget.isConnecting) {
      setState(() {
        _selectedProvider = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    // Get available wallet providers for this token
    final providers = getUIWalletProviders(widget.token.walletType);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Available Wallets',
          style: typography.paragraphNormal(
            fontWeight: ArFontWeight.semiBold,
            color: colorTokens.textHigh,
          ),
        ),
        const SizedBox(height: 12),
        ...providers.map((provider) {
          final isThisProviderConnecting =
              widget.isConnecting && _selectedProvider == provider;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: WalletOptionCard(
              provider: provider,
              isConnecting: isThisProviderConnecting,
              onTap: () {
                setState(() {
                  _selectedProvider = provider;
                });
                widget.onConnect(provider);
              },
            ),
          );
        }),
      ],
    );
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
            child: Text(
              isUserRejected
                  ? 'Connection was rejected. Please try again.'
                  : message,
              style: typography.paragraphSmall(
                color: colorTokens.textMid,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletNotInstalledContent extends StatelessWidget {
  final CryptoTopupWalletNotInstalled state;
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  const _WalletNotInstalledContent({
    required this.state,
    this.onBack,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
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
                  'Wallet Not Found',
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
          const SizedBox(height: 48),

          // Wallet icon
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: colorTokens.containerL2,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.extension_off,
              size: 40,
              color: colorTokens.textMid,
            ),
          ),
          const SizedBox(height: 24),

          // Message
          Text(
            '${state.walletType.displayName} not detected',
            style: typography.heading5(
              fontWeight: ArFontWeight.semiBold,
              color: colorTokens.textHigh,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Please install the ${state.walletType.displayName} browser extension to continue.',
            style: typography.paragraphNormal(
              color: colorTokens.textMid,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Install button
          SizedBox(
            width: double.infinity,
            child: ArDriveButton(
              text: 'Install ${state.walletType.displayName}',
              onPressed: () => _openInstallUrl(state.installUrl),
            ),
          ),
          const SizedBox(height: 12),

          // Back button
          SizedBox(
            width: double.infinity,
            child: ArDriveButton(
              text: 'Choose Different Token',
              style: ArDriveButtonStyle.secondary,
              onPressed: onBack,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openInstallUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _NetworkSwitchingIndicator extends StatelessWidget {
  final CryptoToken token;

  const _NetworkSwitchingIndicator({required this.token});

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
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorTokens.textMid,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Switching Network',
                  style: typography.paragraphNormal(
                    fontWeight: ArFontWeight.semiBold,
                    color: colorTokens.textHigh,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Please confirm the network switch in your wallet',
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
