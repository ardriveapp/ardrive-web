import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/models/wallet_connection_state.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return BlocBuilder<CryptoTopupBloc, CryptoTopupState>(
      builder: (context, state) {
        final showInternalBackButton = _canGoBackInFlow(state);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with back button
            if (showInternalBackButton || onBackToPaymentMethods != null) ...[
              Row(
                children: [
                  InkWell(
                    onTap: () {
                      if (showInternalBackButton) {
                        // Go back within crypto flow
                        context.read<CryptoTopupBloc>().add(const CryptoTopupGoBack());
                      } else if (onBackToPaymentMethods != null) {
                        // Go back to payment method selection
                        onBackToPaymentMethods!();
                      }
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.arrow_back,
                            size: 18,
                            color: colors.themeFgMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            showInternalBackButton ? 'Back' : 'Change payment method',
                            style: typography.paragraphSmall(
                              color: colors.themeFgMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // Token selector
            _TokenSelector(
              selectedToken: _getSelectedToken(state),
              onTokenSelected: (token) {
                context.read<CryptoTopupBloc>().add(CryptoTopupSelectToken(token));
              },
            ),
            const SizedBox(height: 16),

            // Wallet connection status
            _WalletConnectionSection(
              state: state,
              fiatAmount: fiatAmount,
            ),

            // Continue button (only when ready)
            if (_isReadyToContinue(state)) ...[
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ArDriveButton(
                  text: 'Continue',
                  onPressed: onContinue,
                ),
              ),
            ],
          ],
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
      return state.quote != null && !state.balance.hasError;
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
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pay with',
          style: typography.paragraphNormal(
            fontWeight: ArFontWeight.semiBold,
            color: colors.themeFgDefault,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: colors.themeBorderDefault),
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
              _buildTokenMenuItem(context, CryptoToken.arioAO, isRecommended: true),
              _buildTokenMenuItem(context, CryptoToken.ethBase),
              _buildTokenMenuItem(context, CryptoToken.usdcBase),
              _buildTokenMenuItem(context, CryptoToken.sol),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  _TokenIcon(token: selectedToken ?? CryptoToken.arioAO),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selectedToken?.displayName ?? 'Select token',
                          style: typography.paragraphNormal(
                            fontWeight: ArFontWeight.semiBold,
                            color: colors.themeFgDefault,
                          ),
                        ),
                        if (selectedToken != null)
                          Text(
                            selectedToken!.networkDisplayName,
                            style: typography.paragraphSmall(
                              color: colors.themeFgMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.keyboard_arrow_down,
                    color: colors.themeFgMuted,
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
    CryptoToken token, {
    bool isRecommended = false,
  }) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return PopupMenuItem<CryptoToken>(
      value: token,
      child: Row(
        children: [
          _TokenIcon(token: token, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      token.displayName,
                      style: typography.paragraphNormal(
                        fontWeight: ArFontWeight.semiBold,
                        color: colors.themeFgDefault,
                      ),
                    ),
                    if (isRecommended) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.themeSuccessSubtle,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Recommended',
                          style: typography.caption(
                            fontWeight: ArFontWeight.semiBold,
                            color: colors.themeSuccessDefault,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  token.description,
                  style: typography.paragraphSmall(
                    color: colors.themeFgMuted,
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
    final colors = ArDriveTheme.of(context).themeData.colors;
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
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildSelectTokenPrompt(
    BuildContext context,
    ArDriveColors colors,
    ArdriveTypographyNew typography,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.themeBgSubtle,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: colors.themeFgMuted, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Select a token above to see pricing and connect your wallet.',
              style: typography.paragraphSmall(color: colors.themeFgMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletConnectSection(
    BuildContext context,
    CryptoTopupWalletConnection walletState,
    ArDriveColors colors,
    ArdriveTypographyNew typography,
  ) {
    final bloc = context.read<CryptoTopupBloc>();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.themeBgSubtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.themeBorderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Connect Wallet',
            style: typography.paragraphNormal(
              fontWeight: ArFontWeight.semiBold,
              color: colors.themeFgDefault,
            ),
          ),
          const SizedBox(height: 12),

          // Show available wallets based on token type
          if (walletState.token.walletType == WalletType.ethereum) ...[
            _WalletButton(
              label: 'MetaMask',
              icon: Icons.account_balance_wallet,
              isConnecting: walletState.isConnecting,
              onPressed: () {
                bloc.add(const CryptoTopupConnectWallet(
                  ethereumProvider: EthereumWalletProvider.metamask,
                ));
              },
            ),
            const SizedBox(height: 8),
            _WalletButton(
              label: 'Coinbase Wallet',
              icon: Icons.account_balance_wallet,
              isConnecting: walletState.isConnecting,
              onPressed: () {
                bloc.add(const CryptoTopupConnectWallet(
                  ethereumProvider: EthereumWalletProvider.coinbaseWallet,
                ));
              },
            ),
          ] else if (walletState.token.walletType == WalletType.solana) ...[
            _WalletButton(
              label: 'Phantom',
              icon: Icons.account_balance_wallet,
              isConnecting: walletState.isConnecting,
              onPressed: () {
                bloc.add(const CryptoTopupConnectWallet(
                  solanaProvider: SolanaWalletProvider.phantom,
                ));
              },
            ),
            const SizedBox(height: 8),
            _WalletButton(
              label: 'Solflare',
              icon: Icons.account_balance_wallet,
              isConnecting: walletState.isConnecting,
              onPressed: () {
                bloc.add(const CryptoTopupConnectWallet(
                  solanaProvider: SolanaWalletProvider.solflare,
                ));
              },
            ),
          ] else if (walletState.token.walletType == WalletType.arweave) ...[
            // ARIO uses existing ArConnect
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.themeSuccessSubtle,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: colors.themeSuccessDefault, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Using your connected ArConnect wallet',
                      style: typography.paragraphSmall(
                        color: colors.themeSuccessDefault,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ArDriveButton(
                text: 'Continue with ArConnect',
                onPressed: () {
                  bloc.add(const CryptoTopupConnectWallet());
                },
              ),
            ),
          ],

          // Error message
          if (walletState.error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.themeErrorSubtle,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: colors.themeErrorDefault, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      walletState.error!,
                      style: typography.paragraphSmall(
                        color: colors.themeErrorDefault,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuoteSection(
    BuildContext context,
    CryptoTopupAmountEntry amountState,
    ArDriveColors colors,
    ArdriveTypographyNew typography,
  ) {
    final quote = amountState.quote;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.themeBgSubtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.themeBorderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Connected wallet
          Row(
            children: [
              Icon(Icons.check_circle, color: colors.themeSuccessDefault, size: 16),
              const SizedBox(width: 8),
              Text(
                'Wallet connected',
                style: typography.paragraphSmall(
                  color: colors.themeSuccessDefault,
                  fontWeight: ArFontWeight.semiBold,
                ),
              ),
              const Spacer(),
              Text(
                _truncateAddress(amountState.walletAddress),
                style: typography.paragraphSmall(
                  color: colors.themeFgMuted,
                ),
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
                value: '~\$${amountState.gasEstimateUsd?.toStringAsFixed(2) ?? '0.00'}',
                colors: colors,
                typography: typography,
                isMuted: true,
              ),
            ],
          ] else if (amountState.isLoadingQuote) ...[
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            ),
          ],

          // Balance warning
          if (!amountState.hasSufficientBalance && quote != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.themeWarningSubtle,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: colors.themeWarningFg, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Insufficient balance. You have ${amountState.balance.displayBalance}',
                      style: typography.paragraphSmall(
                        color: colors.themeWarningFg,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWalletNotInstalledSection(
    BuildContext context,
    CryptoTopupWalletNotInstalled walletState,
    ArDriveColors colors,
    ArdriveTypographyNew typography,
  ) {
    final walletName = walletState.walletType == WalletType.ethereum
        ? 'MetaMask'
        : walletState.walletType == WalletType.solana
            ? 'Phantom'
            : 'Wallet';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.themeBgSubtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.themeWarningMuted),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber, color: colors.themeWarningFg, size: 20),
              const SizedBox(width: 8),
              Text(
                '$walletName not detected',
                style: typography.paragraphNormal(
                  fontWeight: ArFontWeight.semiBold,
                  color: colors.themeWarningFg,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Please install $walletName browser extension to continue.',
            style: typography.paragraphSmall(color: colors.themeFgMuted),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ArDriveButton(
              style: ArDriveButtonStyle.secondary,
              text: 'Install $walletName',
              onPressed: () {
                // Open install URL in new tab
                // TODO: Use url_launcher
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAOConnectSignatureSection(
    BuildContext context,
    CryptoTopupAOConnectSignature signatureState,
    ArDriveColors colors,
    ArdriveTypographyNew typography,
  ) {
    final bloc = context.read<CryptoTopupBloc>();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.themeBgSubtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.themeBorderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sign Message',
            style: typography.paragraphNormal(
              fontWeight: ArFontWeight.semiBold,
              color: colors.themeFgDefault,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'To use ARIO tokens from your Ethereum wallet, please sign a message to verify your identity.',
            style: typography.paragraphSmall(color: colors.themeFgMuted),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ArDriveButton(
              text: signatureState.isSigningMessage ? 'Signing...' : 'Sign Message',
              isDisabled: signatureState.isSigningMessage,
              onPressed: () {
                bloc.add(const CryptoTopupAOConnectSignatureRequested());
              },
            ),
          ),
          if (signatureState.error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.themeErrorSubtle,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: colors.themeErrorDefault, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      signatureState.isUserRejected
                          ? 'Signature rejected. Please try again.'
                          : signatureState.error!,
                      style: typography.paragraphSmall(
                        color: colors.themeErrorDefault,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNetworkSwitchSection(
    BuildContext context,
    CryptoTopupNetworkSwitch networkState,
    ArDriveColors colors,
    ArdriveTypographyNew typography,
  ) {
    final bloc = context.read<CryptoTopupBloc>();
    final requiredNetworkName = _getNetworkName(networkState.requiredChainId);
    final currentNetworkName = _getNetworkName(networkState.currentChainId);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.themeBgSubtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.themeWarningMuted),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.swap_horiz, color: colors.themeWarningFg, size: 20),
              const SizedBox(width: 8),
              Text(
                'Switch Network',
                style: typography.paragraphNormal(
                  fontWeight: ArFontWeight.semiBold,
                  color: colors.themeWarningFg,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Please switch from $currentNetworkName to $requiredNetworkName to continue.',
            style: typography.paragraphSmall(color: colors.themeFgMuted),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ArDriveButton(
              text: networkState.isSwitching ? 'Switching...' : 'Switch to $requiredNetworkName',
              isDisabled: networkState.isSwitching,
              onPressed: () {
                bloc.add(CryptoTopupNetworkSwitchRequested(networkState.requiredChainId));
              },
            ),
          ),
          if (networkState.error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.themeErrorSubtle,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: colors.themeErrorDefault, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      networkState.error!,
                      style: typography.paragraphSmall(
                        color: colors.themeErrorDefault,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getNetworkName(int chainId) {
    switch (chainId) {
      case 1:
        return 'Ethereum Mainnet';
      case 8453:
        return 'Base';
      default:
        return 'Chain $chainId';
    }
  }

  String _truncateAddress(String address) {
    if (address.length < 10) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }
}

class _QuoteRow extends StatelessWidget {
  final String label;
  final String value;
  final ArDriveColors colors;
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
            color: isMuted ? colors.themeFgMuted : colors.themeFgDefault,
          ),
        ),
        Text(
          value,
          style: typography.paragraphNormal(
            fontWeight: isMuted ? ArFontWeight.book : ArFontWeight.semiBold,
            color: isMuted ? colors.themeFgMuted : colors.themeFgDefault,
          ),
        ),
      ],
    );
  }
}

class _WalletButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isConnecting;
  final VoidCallback onPressed;

  const _WalletButton({
    required this.label,
    required this.icon,
    required this.isConnecting,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    return SizedBox(
      width: double.infinity,
      child: ArDriveButton(
        style: ArDriveButtonStyle.secondary,
        isDisabled: isConnecting,
        icon: isConnecting
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.themeFgMuted,
                ),
              )
            : Icon(icon, size: 18),
        text: isConnecting ? 'Connecting...' : label,
        onPressed: isConnecting ? null : onPressed,
      ),
    );
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
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.themeBgSubtle,
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: Center(
        child: Text(
          token.symbol.substring(0, token.symbol.length > 2 ? 2 : token.symbol.length),
          style: typography.paragraphSmall(
            fontWeight: ArFontWeight.bold,
            color: colors.themeFgDefault,
          ),
        ),
      ),
    );
  }
}
