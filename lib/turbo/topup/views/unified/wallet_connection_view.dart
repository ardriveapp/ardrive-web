import 'package:ardrive/services/arconnect/arconnect.dart';
import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/models/wallet_connection_state.dart';
import 'package:ardrive/turbo/services/ethereum_wallet_service.dart';
import 'package:ardrive/turbo/services/solana_wallet_service.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

/// Simplified wallet connection view for when token is already selected.
///
/// Shows:
/// - Selected token summary
/// - Only installed wallet options (detected at runtime)
/// - Network switching if needed
/// - AO Connect signature if needed
class WalletConnectionView extends StatefulWidget {
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
  State<WalletConnectionView> createState() => _WalletConnectionViewState();
}

class _WalletConnectionViewState extends State<WalletConnectionView> {
  EthereumProviderDetection? _ethereumDetection;
  SolanaProviderDetection? _solanaDetection;
  bool _hasArConnect = false;

  @override
  void initState() {
    super.initState();
    _detectWallets();
  }

  void _detectWallets() {
    final bloc = context.read<CryptoTopupBloc>();

    if (widget.token.walletType == WalletType.ethereum) {
      setState(() {
        _ethereumDetection = bloc.detectEthereumProviders();
      });
    } else if (widget.token.walletType == WalletType.solana) {
      setState(() {
        _solanaDetection = bloc.detectSolanaProviders();
      });
    } else if (widget.token.walletType == WalletType.arweave) {
      // Check if ArConnect extension is installed
      final arConnectService = ArConnectService();
      setState(() {
        _hasArConnect = arConnectService.isExtensionPresent();
      });
    }
  }

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
                              'Connect your ${widget.token.walletType.displayName} to complete the purchase.',
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
                                  _TokenIcon(token: widget.token),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Paying with ${widget.token.displayName}',
                                          style: typography.paragraphNormal(
                                            fontWeight: ArFontWeight.semiBold,
                                            color: colors.themeFgDefault,
                                          ),
                                        ),
                                        Text(
                                          widget.token.networkDisplayName,
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
                      if (widget.onBack != null)
                        ArDriveClickArea(
                          child: GestureDetector(
                            onTap: widget.onBack,
                            child: Text(
                              'Back',
                              style: typography.paragraphLarge(
                                fontWeight: ArFontWeight.bold,
                                color: colors.themeFgMuted,
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
            if (widget.onCancel != null)
              Positioned(
                right: 20,
                top: 20,
                child: ArDriveClickArea(
                  child: GestureDetector(
                    onTap: widget.onCancel,
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
                    '${widget.token.walletType.displayName} not detected. Please install it to continue.',
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
              onPressed: () => _openInstallUrl(widget.token.walletType),
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
                    'Please switch to ${widget.token.networkDisplayName} in your wallet.',
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
                final chainId = widget.token.chainId;
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
                'Connecting to ${widget.token.walletType.displayName}...',
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

  /// Build wallet options based on detected wallets
  Widget _buildWalletOptions(BuildContext context, CryptoTopupBloc bloc) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    // For Arweave wallet (ArConnect), show single connect button
    if (widget.token.walletType == WalletType.arweave) {
      if (!_hasArConnect) {
        return _buildNoWalletsDetected(context, colors, typography);
      }
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
            logoAsset: 'assets/images/wallets/arconnect.png',
            onTap: () => bloc.add(const CryptoTopupConnectWallet()),
          ),
        ],
      );
    }

    // For Ethereum wallets, show only detected wallets
    if (widget.token.walletType == WalletType.ethereum) {
      final detection = _ethereumDetection;
      if (detection == null || !detection.hasAnyProvider) {
        return _buildNoWalletsDetected(context, colors, typography);
      }

      final walletButtons = <Widget>[];

      if (detection.hasMetaMask) {
        walletButtons.add(_WalletOptionButton(
          name: 'MetaMask',
          logoAsset: 'assets/images/login/metamask_logo_flat.svg',
          onTap: () => bloc.add(const CryptoTopupConnectWallet(
            ethereumProvider: EthereumWalletProvider.metamask,
          )),
        ));
      }

      if (detection.hasCoinbaseWallet) {
        if (walletButtons.isNotEmpty) {
          walletButtons.add(const SizedBox(height: 8));
        }
        walletButtons.add(_WalletOptionButton(
          name: 'Coinbase Wallet',
          logoAsset: 'assets/images/wallets/coinbase.png',
          onTap: () => bloc.add(const CryptoTopupConnectWallet(
            ethereumProvider: EthereumWalletProvider.coinbaseWallet,
          )),
        ));
      }

      if (detection.hasRainbow) {
        if (walletButtons.isNotEmpty) {
          walletButtons.add(const SizedBox(height: 8));
        }
        walletButtons.add(_WalletOptionButton(
          name: 'Rainbow',
          logoAsset: 'assets/images/wallets/rainbow.png',
          onTap: () => bloc.add(const CryptoTopupConnectWallet(
            ethereumProvider: EthereumWalletProvider.rainbow,
          )),
        ));
      }

      if (detection.hasBrave) {
        if (walletButtons.isNotEmpty) {
          walletButtons.add(const SizedBox(height: 8));
        }
        walletButtons.add(_WalletOptionButton(
          name: 'Brave Wallet',
          logoAsset: 'assets/images/wallets/brave.png',
          onTap: () => bloc.add(const CryptoTopupConnectWallet(
            ethereumProvider: EthereumWalletProvider.metamask, // Brave uses MetaMask interface
          )),
        ));
      }

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
          ...walletButtons,
        ],
      );
    }

    // For Solana wallets, show only detected wallets
    if (widget.token.walletType == WalletType.solana) {
      final detection = _solanaDetection;
      if (detection == null || !detection.hasAnyProvider) {
        return _buildNoWalletsDetected(context, colors, typography);
      }

      final walletButtons = <Widget>[];

      if (detection.hasPhantom) {
        walletButtons.add(_WalletOptionButton(
          name: 'Phantom',
          logoAsset: 'assets/images/wallets/phantom.svg',
          onTap: () => bloc.add(const CryptoTopupConnectWallet(
            solanaProvider: SolanaWalletProvider.phantom,
          )),
        ));
      }

      if (detection.hasSolflare) {
        if (walletButtons.isNotEmpty) {
          walletButtons.add(const SizedBox(height: 8));
        }
        walletButtons.add(_WalletOptionButton(
          name: 'Solflare',
          logoAsset: 'assets/images/wallets/solflare.svg',
          onTap: () => bloc.add(const CryptoTopupConnectWallet(
            solanaProvider: SolanaWalletProvider.solflare,
          )),
        ));
      }

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
          ...walletButtons,
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

  /// Build message when no wallets are detected
  Widget _buildNoWalletsDetected(
    BuildContext context,
    ArDriveColors colors,
    ArdriveTypographyNew typography,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.themeWarningSubtle,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: colors.themeWarningFg),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No wallets detected',
                      style: typography.paragraphNormal(
                        fontWeight: ArFontWeight.semiBold,
                        color: colors.themeWarningFg,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _getInstallInstructions(),
                style: typography.paragraphSmall(
                  color: colors.themeFgMuted,
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
            onPressed: () => _openInstallUrl(widget.token.walletType),
          ),
        ),
      ],
    );
  }

  String _getInstallInstructions() {
    return switch (widget.token.walletType) {
      WalletType.ethereum =>
        'Please install a wallet extension like MetaMask or Coinbase Wallet to continue.',
      WalletType.solana =>
        'Please install Phantom or Solflare to continue.',
      WalletType.arweave => 'Please install ArConnect to continue.',
    };
  }

  /// Gets the specific wallet app name based on wallet type
  String _getWalletAppName() {
    return switch (widget.token.walletType) {
      WalletType.arweave => 'ArConnect',
      WalletType.ethereum => 'MetaMask',
      WalletType.solana => 'Phantom',
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

/// A styled wallet option button with logo
class _WalletOptionButton extends StatelessWidget {
  final String name;
  final String logoAsset;
  final VoidCallback onTap;

  const _WalletOptionButton({
    required this.name,
    required this.logoAsset,
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
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _buildLogo(),
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

  Widget _buildLogo() {
    final isSvg = logoAsset.endsWith('.svg');

    if (isSvg) {
      return SvgPicture.asset(
        logoAsset,
        width: 36,
        height: 36,
        fit: BoxFit.contain,
      );
    } else {
      return Image.asset(
        logoAsset,
        width: 36,
        height: 36,
        fit: BoxFit.contain,
      );
    }
  }
}

class _TokenIcon extends StatelessWidget {
  final CryptoToken token;

  const _TokenIcon({required this.token});

  @override
  Widget build(BuildContext context) {
    final isSvg = token.logoAsset.endsWith('.svg');

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: _getTokenColor(token),
        borderRadius: BorderRadius.circular(20),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: isSvg
            ? SvgPicture.asset(
                token.logoAsset,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                placeholderBuilder: (context) => _buildFallback(),
              )
            : Image.asset(
                token.logoAsset,
                width: 40,
                height: 40,
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
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
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
