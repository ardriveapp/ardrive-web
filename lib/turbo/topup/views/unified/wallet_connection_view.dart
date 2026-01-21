import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/models/wallet_connection_state.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

/// Simplified wallet connection view for when token is already selected.
///
/// Shows:
/// - Selected token summary
/// - Wallet options directly (no extra button click)
/// - Network switching if needed
/// - AO Connect signature if needed
class WalletConnectionView extends StatelessWidget {
  final CryptoToken token;
  final double fiatAmount;
  final VoidCallback? onBack;
  final VoidCallback? onCancel;

  const WalletConnectionView({
    super.key,
    required this.token,
    required this.fiatAmount,
    this.onBack,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return BlocBuilder<CryptoTopupBloc, CryptoTopupState>(
      builder: (context, state) {
        return Stack(
          children: [
            Column(
              children: [
                // Red top line (ArDrive modal pattern)
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
                // Main content
                Expanded(
                  child: Container(
                    color: colors.themeBgCanvas,
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 24), // Space for close button
                            // Title
                            Text(
                              'Connect Wallet',
                              style: typography.heading5(
                                fontWeight: ArFontWeight.bold,
                                color: colors.themeFgDefault,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Connect your ${token.walletType.displayName} to complete the purchase.',
                              style: typography.paragraphNormal(
                                color: colors.themeFgMuted,
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Payment summary card
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: colors.themeBgSubtle,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: colors.themeBorderDefault),
                              ),
                              child: Row(
                                children: [
                                  _TokenIcon(token: token),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Paying with ${token.displayName}',
                                          style: typography.paragraphNormal(
                                            fontWeight: ArFontWeight.semiBold,
                                            color: colors.themeFgDefault,
                                          ),
                                        ),
                                        Text(
                                          token.networkDisplayName,
                                          style: typography.paragraphSmall(
                                            color: colors.themeFgMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Connection status and action
                            _buildConnectionContent(context, state),

                            const SizedBox(height: 48), // Space for footer
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Footer with back button
                Container(
                  color: colors.themeBgCanvas,
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (onBack != null)
                        ArDriveClickArea(
                          child: GestureDetector(
                            onTap: onBack,
                            child: Text(
                              'Back',
                              style: typography.paragraphLarge(
                                fontWeight: ArFontWeight.bold,
                                color: colors.themeAccentDisabled,
                              ),
                            ),
                          ),
                        )
                      else
                        const SizedBox.shrink(),
                      const Spacer(),
                    ],
                  ),
                ),
              ],
            ),
            // Close button in top right
            if (onCancel != null)
              Positioned(
                right: 27,
                top: 27,
                child: ArDriveClickArea(
                  child: GestureDetector(
                    onTap: onCancel,
                    child: ArDriveIcons.x(),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildConnectionContent(BuildContext context, CryptoTopupState state) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);
    final bloc = context.read<CryptoTopupBloc>();

    // Wallet not installed
    if (state is CryptoTopupWalletNotInstalled) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.themeErrorSubtle,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber, color: colors.themeErrorDefault),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${token.walletType.displayName} not detected. Please install it to continue.',
                    style: typography.paragraphNormal(
                      color: colors.themeErrorDefault,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ArDriveButton(
              text: 'Install ${_getWalletAppName()}',
              onPressed: () => _openInstallUrl(token.walletType),
            ),
          ),
        ],
      );
    }

    // AO Connect signature needed
    if (state is CryptoTopupAOConnectSignature) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.themeBgSubtle,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.themeBorderDefault),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Please sign the message in your Ethereum wallet to continue.',
                style: typography.paragraphNormal(
                  color: colors.themeFgDefault,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Network switch needed
    if (state is CryptoTopupNetworkSwitch) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.themeBgSubtle,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.themeBorderDefault),
            ),
            child: Row(
              children: [
                Icon(Icons.swap_horiz, color: colors.themeFgMuted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Please switch to ${token.networkDisplayName} in your wallet.',
                    style: typography.paragraphNormal(
                      color: colors.themeFgDefault,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ArDriveButton(
              text: 'Switch Network',
              onPressed: () {
                final chainId = token.chainId;
                if (chainId != null) {
                  bloc.add(CryptoTopupSwitchNetwork(chainId));
                }
              },
            ),
          ),
        ],
      );
    }

    // Connecting
    if (state is CryptoTopupWalletConnection && state.isConnecting) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.themeBgSubtle,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.themeBorderDefault),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Connecting to ${token.walletType.displayName}...',
                style: typography.paragraphNormal(
                  color: colors.themeFgDefault,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Default: show wallet options directly
    return _buildWalletOptions(context, bloc);
  }

  /// Build wallet options inline instead of requiring a button click
  Widget _buildWalletOptions(BuildContext context, CryptoTopupBloc bloc) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    // For Arweave wallet (ArConnect), show single connect button
    if (token.walletType == WalletType.arweave) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select Wallet',
            style: typography.paragraphNormal(
              fontWeight: ArFontWeight.semiBold,
              color: colors.themeFgDefault,
            ),
          ),
          const SizedBox(height: 12),
          _WalletOptionButton(
            name: 'ArConnect',
            icon: Icons.account_balance_wallet,
            iconColor: const Color(0xFFAB9AFF),
            onTap: () => bloc.add(const CryptoTopupConnectWallet()),
          ),
        ],
      );
    }

    // For Ethereum wallets, show common options
    if (token.walletType == WalletType.ethereum) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select Wallet',
            style: typography.paragraphNormal(
              fontWeight: ArFontWeight.semiBold,
              color: colors.themeFgDefault,
            ),
          ),
          const SizedBox(height: 12),
          _WalletOptionButton(
            name: 'MetaMask',
            icon: Icons.account_balance_wallet,
            iconColor: const Color(0xFFE2761B),
            onTap: () => bloc.add(const CryptoTopupConnectWallet(
              ethereumProvider: EthereumWalletProvider.metamask,
            )),
          ),
          const SizedBox(height: 8),
          _WalletOptionButton(
            name: 'Coinbase Wallet',
            icon: Icons.account_balance_wallet,
            iconColor: const Color(0xFF0052FF),
            onTap: () => bloc.add(const CryptoTopupConnectWallet(
              ethereumProvider: EthereumWalletProvider.coinbaseWallet,
            )),
          ),
          const SizedBox(height: 8),
          _WalletOptionButton(
            name: 'Other Wallet (Browser)',
            icon: Icons.public,
            iconColor: colors.themeFgMuted,
            onTap: () => bloc.add(const CryptoTopupConnectWallet(
              ethereumProvider: null, // Uses default injected provider
            )),
          ),
        ],
      );
    }

    // For Solana wallets
    if (token.walletType == WalletType.solana) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select Wallet',
            style: typography.paragraphNormal(
              fontWeight: ArFontWeight.semiBold,
              color: colors.themeFgDefault,
            ),
          ),
          const SizedBox(height: 12),
          _WalletOptionButton(
            name: 'Phantom',
            icon: Icons.account_balance_wallet,
            iconColor: const Color(0xFFAB9AFF),
            onTap: () => bloc.add(const CryptoTopupConnectWallet(
              solanaProvider: SolanaWalletProvider.phantom,
            )),
          ),
          const SizedBox(height: 8),
          _WalletOptionButton(
            name: 'Solflare',
            icon: Icons.account_balance_wallet,
            iconColor: const Color(0xFFFC8C1C),
            onTap: () => bloc.add(const CryptoTopupConnectWallet(
              solanaProvider: SolanaWalletProvider.solflare,
            )),
          ),
          const SizedBox(height: 8),
          _WalletOptionButton(
            name: 'Other Wallet (Browser)',
            icon: Icons.public,
            iconColor: colors.themeFgMuted,
            onTap: () => bloc.add(const CryptoTopupConnectWallet(
              solanaProvider: null, // Uses default
            )),
          ),
        ],
      );
    }

    // Fallback: generic connect button
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ArDriveButton(
        text: 'Connect ${_getWalletAppName()}',
        onPressed: () => bloc.add(const CryptoTopupConnectWallet()),
      ),
    );
  }

  /// Gets the specific wallet app name based on wallet type
  String _getWalletAppName() {
    return switch (token.walletType) {
      WalletType.arweave => 'ArConnect',
      WalletType.ethereum => 'Wallet',
      WalletType.solana => 'Wallet',
    };
  }

  /// Opens the wallet install URL in an external browser
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
}

/// A styled wallet option button
class _WalletOptionButton extends StatelessWidget {
  final String name;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;

  const _WalletOptionButton({
    required this.name,
    required this.icon,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: colors.themeBgSubtle,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.themeBorderDefault),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                size: 20,
                color: iconColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: typography.paragraphNormal(
                  fontWeight: ArFontWeight.semiBold,
                  color: colors.themeFgDefault,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: colors.themeFgMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _TokenIcon extends StatelessWidget {
  final CryptoToken token;

  const _TokenIcon({required this.token});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: _getTokenColor(token),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Text(
          _getTokenAbbreviation(token),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
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

  Color _getTokenColor(CryptoToken token) {
    switch (token) {
      case CryptoToken.arioAO:
      case CryptoToken.arioAOViaEth:
      case CryptoToken.arioBase:
        return const Color(0xFF000000);
      case CryptoToken.ethL1:
      case CryptoToken.ethBase:
        return const Color(0xFF627EEA);
      case CryptoToken.sol:
        return const Color(0xFF9945FF);
      case CryptoToken.usdcBase:
      case CryptoToken.usdcEth:
        return const Color(0xFF2775CA);
    }
  }
}
