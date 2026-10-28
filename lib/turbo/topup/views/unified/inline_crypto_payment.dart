import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive/turbo/topup/components/turbo_topup_scaffold.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/views/crypto_topup/components/network_indicator.dart';
import 'package:ardrive/turbo/topup/views/crypto_topup/components/wallet_selector_modal.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

/// Inline crypto payment section that appears within the main top-up dialog.
///
/// Shows token selection, wallet connection, and price estimate in a compact
/// inline format rather than a separate modal.
class InlineCryptoPayment extends StatelessWidget {
  final double fiatAmount;
  final VoidCallback? onContinue;
  final VoidCallback? onCancel;

  /// Called when user wants to go back to payment method selection
  final VoidCallback? onBackToPaymentMethods;

  const InlineCryptoPayment({
    super.key,
    required this.fiatAmount,
    this.onContinue,
    this.onCancel,
    this.onBackToPaymentMethods,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CryptoTopupBloc, CryptoTopupState>(
      builder: (context, state) {
        final showInternalBackButton = _canGoBackInFlow(state);
        final showBackButton =
            showInternalBackButton || onBackToPaymentMethods != null;

        return TurboTopupScaffold(
          title: 'Buy Turbo Credits',
          onClose: onCancel,
          canClose: onCancel != null,
          actions: [
            if (showBackButton)
              ModalAction.dismiss(
                title: 'Back',
                action: () {
                  if (showInternalBackButton) {
                    // Go back within crypto flow
                    context
                        .read<CryptoTopupBloc>()
                        .add(const CryptoTopupGoBack());
                  } else if (onBackToPaymentMethods != null) {
                    // Go back to payment method selection
                    onBackToPaymentMethods!();
                  }
                },
              ),
            if (_isReadyToContinue(state) && onContinue != null)
              ModalAction(title: 'Continue', action: onContinue!),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Token selector
              _TokenSelector(
                selectedToken: _getSelectedToken(state),
                onTokenSelected: (token) {
                  context
                      .read<CryptoTopupBloc>()
                      .add(CryptoTopupSelectToken(token));
                },
              ),
              const SizedBox(height: 16),

              // Wallet connection status
              _WalletConnectionSection(
                state: state,
                fiatAmount: fiatAmount,
              ),
            ],
          ),
        );
      },
    );
  }

  /// Check if we can go back within the crypto flow
  bool _canGoBackInFlow(CryptoTopupState state) {
    // Can go back from wallet connection to token selection
    if (state is CryptoTopupWalletConnection) return true;
    // Can go back from amount entry to token selection
    if (state is CryptoTopupAmountEntry) return true;
    // Can go back from wallet not installed to token selection
    if (state is CryptoTopupWalletNotInstalled) return true;
    // Can go back from AO signature to token selection
    if (state is CryptoTopupAOConnectSignature) return true;
    // Can go back from network switch to token selection
    if (state is CryptoTopupNetworkSwitch) return true;
    return false;
  }

  CryptoToken? _getSelectedToken(CryptoTopupState state) {
    if (state is CryptoTopupTokenSelection) return null;
    if (state is CryptoTopupWalletConnection) return state.token;
    if (state is CryptoTopupWalletNotInstalled) return state.token;
    if (state is CryptoTopupAmountEntry) return state.token;
    if (state is CryptoTopupConfirmation) return state.token;
    return null;
  }

  bool _isReadyToContinue(CryptoTopupState state) {
    if (state is CryptoTopupAmountEntry) {
      return state.quote != null &&
          !state.quote!.isExpired &&
          !state.balance.hasError &&
          state.hasSufficientBalance;
    }
    return false;
  }
}

/// Token dropdown selector
class _TokenSelector extends StatelessWidget {
  final CryptoToken? selectedToken;
  final ValueChanged<CryptoToken> onTokenSelected;

  const _TokenSelector({
    this.selectedToken,
    required this.onTokenSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pay with',
          style: typography.paragraphNormal(
            fontWeight: ArFontWeight.semiBold,
            color: colors.textHigh,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: colors.strokeMid),
            borderRadius: BorderRadius.circular(8),
          ),
          child: PopupMenuButton<CryptoToken>(
            initialValue: selectedToken,
            onSelected: onTokenSelected,
            offset: const Offset(0, 48),
            constraints: const BoxConstraints(minWidth: 280),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            itemBuilder: (context) => [
              // Base L2 tokens (fast, low fees)
              _buildTokenMenuItem(context, CryptoToken.ethBase),
              _buildTokenMenuItem(context, CryptoToken.usdcBase),
              // Solana
              _buildTokenMenuItem(context, CryptoToken.sol),
              // Ethereum L1 tokens (slower, higher fees)
              _buildTokenMenuItem(context, CryptoToken.ethL1),
              _buildTokenMenuItem(context, CryptoToken.usdcEth),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Only show token icon if a token is selected
                  if (selectedToken != null) ...[
                    _TokenIcon(token: selectedToken!),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selectedToken?.displayName ?? 'Select token',
                          style: typography.paragraphNormal(
                            fontWeight: ArFontWeight.semiBold,
                            color: selectedToken != null
                                ? colors.textHigh
                                : colors.textMid,
                          ),
                        ),
                        if (selectedToken != null)
                          Text(
                            selectedToken!.networkDisplayName,
                            style: typography.paragraphSmall(
                              color: colors.textMid,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.keyboard_arrow_down,
                    color: colors.textMid,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  PopupMenuItem<CryptoToken> _buildTokenMenuItem(
    BuildContext context,
    CryptoToken token,
  ) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    // ARIO tokens have no fees
    final isNoFees = token == CryptoToken.arioAO ||
        token == CryptoToken.arioAOViaEth ||
        token == CryptoToken.arioBase;

    return PopupMenuItem<CryptoToken>(
      value: token,
      child: Row(
        children: [
          _TokenIcon(token: token, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                Text(
                  token.displayName,
                  style: typography.paragraphNormal(
                    fontWeight: ArFontWeight.semiBold,
                    color: colors.textHigh,
                  ),
                ),
                if (isNoFees) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.containerRaised,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: colors.strokeMid),
                    ),
                    child: Text(
                      'No Turbo fee',
                      style: typography.caption(
                        fontWeight: ArFontWeight.semiBold,
                        color: colors.textMid,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Wallet connection section - shows status and connect button
class _WalletConnectionSection extends StatelessWidget {
  final CryptoTopupState state;
  final double fiatAmount;

  const _WalletConnectionSection({
    required this.state,
    required this.fiatAmount,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    // Token selection state - need to select token first
    if (state is CryptoTopupTokenSelection) {
      return _buildSelectTokenPrompt(context, colors, typography);
    }

    // Wallet connection state
    if (state is CryptoTopupWalletConnection) {
      return _buildWalletConnectSection(
        context,
        state as CryptoTopupWalletConnection,
        colors,
        typography,
      );
    }

    // Wallet not installed state
    if (state is CryptoTopupWalletNotInstalled) {
      return _buildWalletNotInstalledSection(
        context,
        state as CryptoTopupWalletNotInstalled,
        colors,
        typography,
      );
    }

    // AO Connect signature state (for ARIO via ETH)
    if (state is CryptoTopupAOConnectSignature) {
      return _buildAOConnectSignatureSection(
        context,
        state as CryptoTopupAOConnectSignature,
        colors,
        typography,
      );
    }

    // Network switch state
    if (state is CryptoTopupNetworkSwitch) {
      return _buildNetworkSwitchSection(
        context,
        state as CryptoTopupNetworkSwitch,
        colors,
        typography,
      );
    }

    // Amount entry state - wallet connected, show quote
    if (state is CryptoTopupAmountEntry) {
      return _buildQuoteSection(
        context,
        state as CryptoTopupAmountEntry,
        colors,
        typography,
      );
    }

    // Loading state
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(child: ArDriveSpinner(size: ArDriveSpinnerSize.large)),
    );
  }

  Widget _buildSelectTokenPrompt(
    BuildContext context,
    ArDriveColorTokens colors,
    ArdriveTypographyNew typography,
  ) {
    return const ArDriveNotice(
      type: ArDriveNoticeType.info,
      message: 'Select a token above to see pricing and connect your wallet.',
    );
  }

  Widget _buildWalletConnectSection(
    BuildContext context,
    CryptoTopupWalletConnection walletState,
    ArDriveColorTokens colors,
    ArdriveTypographyNew typography,
  ) {
    final bloc = context.read<CryptoTopupBloc>();
    final walletType = walletState.token.walletType;

    // Get detected wallets based on type - uses actual JS bridge detection
    final detectedWallets = _getDetectedWallets(context, walletType);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.containerRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.strokeMid),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Connect wallet',
            style: typography.paragraphNormal(
              fontWeight: ArFontWeight.semiBold,
              color: colors.textHigh,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _getWalletSubtitle(walletType),
            style: typography.paragraphSmall(
              color: colors.textMid,
            ),
          ),
          const SizedBox(height: 16),

          // Show network switching message if applicable
          if (walletState.isSwitchingNetwork) ...[
            ArDriveNotice(
              type: ArDriveNoticeType.info,
              content: Row(
                children: [
                  ArDriveSpinner(color: colors.statusInfoFg),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Switching network in your wallet...'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Arweave uses existing ArConnect
          if (walletType == WalletType.arweave) ...[
            const ArDriveNotice(
              type: ArDriveNoticeType.success,
              message: 'Using your connected ArConnect wallet',
            ),
            const SizedBox(height: 12),
            ArDriveButtonNew(
              typography: ArDriveTypographyNew.of(context),
              variant: ButtonVariant.primary,
              size: ArDriveButtonSize.large,
              maxWidth: double.infinity,
              text: 'Continue with ArConnect',
              onPressed: () {
                bloc.add(const CryptoTopupConnectWallet());
              },
            ),
          ] else ...[
            // Show wallet grid for Ethereum/Solana
            _WalletGrid(
              wallets: detectedWallets,
              isConnecting: walletState.isConnecting,
              onWalletSelected: (wallet) {
                bloc.add(CryptoTopupConnectWallet(
                  ethereumProvider: wallet.ethereumProvider,
                  solanaProvider: wallet.solanaProvider,
                ));
              },
            ),
          ],

          // Error message
          if (walletState.error != null && !walletState.isSwitchingNetwork) ...[
            const SizedBox(height: 12),
            ArDriveNotice(
              type: ArDriveNoticeType.error,
              message: walletState.error!,
            ),
          ],
        ],
      ),
    );
  }

  List<DetectedWallet> _getDetectedWallets(
    BuildContext context,
    WalletType walletType,
  ) {
    final bloc = context.read<CryptoTopupBloc>();

    if (walletType == WalletType.ethereum) {
      final detection = bloc.detectEthereumProviders();
      return DetectedWallet.fromEthereumDetection(
        hasMetaMask: detection.hasMetaMask,
        hasCoinbase: detection.hasCoinbaseWallet,
        hasRainbow: detection.hasRainbow,
        hasTrust: false, // Not currently detected by JS bridge
        hasBrave: detection.hasBrave,
      );
    } else if (walletType == WalletType.solana) {
      final detection = bloc.detectSolanaProviders();
      return DetectedWallet.fromSolanaDetection(
        hasPhantom: detection.hasPhantom,
        hasSolflare: detection.hasSolflare,
      );
    }
    return [];
  }

  String _getWalletSubtitle(WalletType walletType) {
    switch (walletType) {
      case WalletType.ethereum:
        return 'Choose your Ethereum wallet';
      case WalletType.solana:
        return 'Choose your Solana wallet';
      case WalletType.arweave:
        return 'Connect with ArConnect';
    }
  }

  Widget _buildQuoteSection(
    BuildContext context,
    CryptoTopupAmountEntry amountState,
    ArDriveColorTokens colors,
    ArdriveTypographyNew typography,
  ) {
    final quote = amountState.quote;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.containerRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.strokeMid),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Connected wallet
          Row(
            children: [
              Icon(Icons.check_circle, color: colors.textMid, size: 16),
              const SizedBox(width: 8),
              Text(
                'Wallet connected',
                style: typography.paragraphSmall(
                  color: colors.textHigh,
                  fontWeight: ArFontWeight.semiBold,
                ),
              ),
              const Spacer(),
              Text(
                _truncateAddress(amountState.walletAddress),
                style: typography.code(color: colors.textMid),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // Quote details
          if (quote != null) ...[
            _QuoteRow(
              label: 'You pay',
              value: quote.formattedTokenAmount,
              colors: colors,
              typography: typography,
            ),
            const SizedBox(height: 8),
            _QuoteRow(
              label: 'You receive',
              value: quote.formattedCredits,
              colors: colors,
              typography: typography,
            ),
            if (amountState.token.requiresGasEstimation) ...[
              const SizedBox(height: 8),
              _QuoteRow(
                label: 'Est. network fee',
                value:
                    '~\$${amountState.gasEstimateUsd?.toStringAsFixed(2) ?? '0.00'}',
                colors: colors,
                typography: typography,
                isMuted: true,
              ),
            ],
          ] else if (amountState.isLoadingQuote) ...[
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: ArDriveSpinner(size: ArDriveSpinnerSize.large),
              ),
            ),
          ],

          // Balance warning
          if (!amountState.hasSufficientBalance && quote != null) ...[
            const SizedBox(height: 16),
            ArDriveNotice(
              type: ArDriveNoticeType.warning,
              message:
                  'Insufficient balance. You have ${amountState.balance.displayBalance}',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWalletNotInstalledSection(
    BuildContext context,
    CryptoTopupWalletNotInstalled walletState,
    ArDriveColorTokens colors,
    ArdriveTypographyNew typography,
  ) {
    final walletName = walletState.walletType == WalletType.ethereum
        ? 'MetaMask'
        : walletState.walletType == WalletType.solana
            ? 'Phantom'
            : 'Wallet';

    return ArDriveNotice(
      type: ArDriveNoticeType.warning,
      title: '$walletName not detected',
      message: 'Please install $walletName browser extension to continue.',
      actionLabel: 'Install $walletName',
      onAction: () {
        _openInstallUrl(walletState.walletType);
      },
    );
  }

  Future<void> _openInstallUrl(WalletType walletType) async {
    final url = switch (walletType) {
      WalletType.ethereum => 'https://metamask.io/download/',
      WalletType.solana => 'https://phantom.app/download',
      WalletType.arweave => 'https://www.arconnect.io/download',
    };
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildAOConnectSignatureSection(
    BuildContext context,
    CryptoTopupAOConnectSignature signatureState,
    ArDriveColorTokens colors,
    ArdriveTypographyNew typography,
  ) {
    final bloc = context.read<CryptoTopupBloc>();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.containerRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.strokeMid),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sign message',
            style: typography.paragraphNormal(
              fontWeight: ArFontWeight.semiBold,
              color: colors.textHigh,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'To use ARIO tokens from your Ethereum wallet, please sign a message to verify your identity.',
            style: typography.paragraphSmall(color: colors.textMid),
          ),
          const SizedBox(height: 16),
          ArDriveButtonNew(
            typography: ArDriveTypographyNew.of(context),
            variant: ButtonVariant.primary,
            size: ArDriveButtonSize.large,
            maxWidth: double.infinity,
            text:
                signatureState.isSigningMessage ? 'Signing...' : 'Sign message',
            isDisabled: signatureState.isSigningMessage,
            onPressed: () {
              bloc.add(const CryptoTopupAOConnectSignatureRequested());
            },
          ),
          if (signatureState.error != null) ...[
            const SizedBox(height: 12),
            ArDriveNotice(
              type: ArDriveNoticeType.error,
              message: signatureState.isUserRejected
                  ? 'Signature rejected. Please try again.'
                  : signatureState.error!,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNetworkSwitchSection(
    BuildContext context,
    CryptoTopupNetworkSwitch networkState,
    ArDriveColorTokens colors,
    ArdriveTypographyNew typography,
  ) {
    final bloc = context.read<CryptoTopupBloc>();
    final requiredNetworkName = getNetworkName(networkState.requiredChainId);
    final currentNetworkName = getNetworkName(networkState.currentChainId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ArDriveNotice(
          type: ArDriveNoticeType.warning,
          title: 'Switch network',
          message:
              'Please switch from $currentNetworkName to $requiredNetworkName to continue.',
        ),
        const SizedBox(height: 16),
        ArDriveButtonNew(
          typography: ArDriveTypographyNew.of(context),
          variant: ButtonVariant.primary,
          size: ArDriveButtonSize.large,
          maxWidth: double.infinity,
          text: networkState.isSwitching
              ? 'Switching...'
              : 'Switch to $requiredNetworkName',
          isDisabled: networkState.isSwitching,
          onPressed: () {
            bloc.add(CryptoTopupNetworkSwitchRequested(
                networkState.requiredChainId));
          },
        ),
        if (networkState.error != null) ...[
          const SizedBox(height: 12),
          ArDriveNotice(
            type: ArDriveNoticeType.error,
            message: networkState.error!,
          ),
        ],
      ],
    );
  }

  String _truncateAddress(String address) {
    if (address.length < 10) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }
}

class _QuoteRow extends StatelessWidget {
  final String label;
  final String value;
  final ArDriveColorTokens colors;
  final ArdriveTypographyNew typography;
  final bool isMuted;

  const _QuoteRow({
    required this.label,
    required this.value,
    required this.colors,
    required this.typography,
    this.isMuted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: typography.paragraphNormal(
            color: isMuted ? colors.textMid : colors.textHigh,
          ),
        ),
        Text(
          value,
          style: typography.paragraphNormal(
            fontWeight: isMuted ? ArFontWeight.book : ArFontWeight.semiBold,
            color: isMuted ? colors.textMid : colors.textHigh,
          ),
        ),
      ],
    );
  }
}

/// Grid of wallet options (RainbowKit-style)
class _WalletGrid extends StatelessWidget {
  final List<DetectedWallet> wallets;
  final bool isConnecting;
  final ValueChanged<DetectedWallet> onWalletSelected;

  const _WalletGrid({
    required this.wallets,
    required this.isConnecting,
    required this.onWalletSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: wallets.map((wallet) {
        return _WalletGridItem(
          wallet: wallet,
          isConnecting: isConnecting,
          onTap: () => onWalletSelected(wallet),
          colors: colors,
          typography: typography,
        );
      }).toList(),
    );
  }
}

/// Individual wallet item in the grid
class _WalletGridItem extends StatelessWidget {
  final DetectedWallet wallet;
  final bool isConnecting;
  final VoidCallback onTap;
  final ArDriveColorTokens colors;
  final ArdriveTypographyNew typography;

  const _WalletGridItem({
    required this.wallet,
    required this.isConnecting,
    required this.onTap,
    required this.colors,
    required this.typography,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isConnecting ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 100,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: colors.containerRaised,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.strokeMid),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Wallet icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _getWalletColor(),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: isConnecting
                      // White on the wallet's brand colour, below.
                      ? const ArDriveSpinner(color: Colors.white)
                      : Text(
                          wallet.displayName.substring(0, 1).toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              // Wallet name
              Text(
                wallet.displayName,
                style: typography.paragraphSmall(
                  fontWeight: ArFontWeight.semiBold,
                  color: colors.textHigh,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              // Detected badge
              if (wallet.isInstalled) ...[
                const SizedBox(height: 2),
                Text(
                  'Detected',
                  style: typography.caption(
                    color: colors.statusSuccessFg,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // The wallets' own brand colours, not ArDrive's.
  Color _getWalletColor() {
    switch (wallet.id) {
      case 'metamask':
        return const Color(0xFFE2761B); // MetaMask orange
      case 'coinbase':
        return const Color(0xFF0052FF); // Coinbase blue
      case 'rainbow':
        return const Color(0xFF001E59); // Rainbow dark blue
      case 'trust':
        return const Color(0xFF3375BB); // Trust blue
      case 'brave':
        return const Color(0xFFFF5500); // Brave orange
      case 'phantom':
        return const Color(0xFFAB9FF2); // Phantom purple
      case 'solflare':
        return const Color(0xFFFC8C03); // Solflare orange
      case 'walletconnect':
        return const Color(0xFF3B99FC); // WalletConnect blue
      default:
        return colors.textMid;
    }
  }
}

class _TokenIcon extends StatelessWidget {
  final CryptoToken token;
  final double size;

  const _TokenIcon({
    required this.token,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final isSvg = token.logoAsset.endsWith('.svg');

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _getTokenColor(token),
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: isSvg
            ? SvgPicture.asset(
                token.logoAsset,
                width: size,
                height: size,
                fit: BoxFit.cover,
                placeholderBuilder: (context) => _buildFallback(),
              )
            : Image.asset(
                token.logoAsset,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _buildFallback(),
              ),
      ),
    );
  }

  Widget _buildFallback() {
    return Center(
      child: Text(
        _getTokenAbbreviation(token),
        style: TextStyle(
          fontSize: size * 0.35,
          fontWeight: FontWeight.bold,
          // On the token's brand colour, below.
          color: Colors.white,
        ),
      ),
    );
  }

  String _getTokenAbbreviation(CryptoToken token) {
    return switch (token) {
      CryptoToken.arioAO ||
      CryptoToken.arioAOViaEth ||
      CryptoToken.arioBase =>
        'AR',
      CryptoToken.ethL1 || CryptoToken.ethBase => 'ETH',
      CryptoToken.sol => 'SOL',
      CryptoToken.usdcBase || CryptoToken.usdcEth => 'USD',
    };
  }

  // The tokens' own brand colours, not ArDrive's.
  Color _getTokenColor(CryptoToken token) {
    return switch (token) {
      CryptoToken.arioAO ||
      CryptoToken.arioAOViaEth ||
      CryptoToken.arioBase =>
        const Color(0xFF000000),
      CryptoToken.ethL1 || CryptoToken.ethBase => const Color(0xFF627EEA),
      CryptoToken.sol => const Color(0xFF9945FF),
      CryptoToken.usdcBase || CryptoToken.usdcEth => const Color(0xFF2775CA),
    };
  }
}
