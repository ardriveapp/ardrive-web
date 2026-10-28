import 'package:ardrive/services/arconnect/arconnect.dart';
import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive/turbo/topup/components/turbo_topup_scaffold.dart';
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
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final onBack = widget.onBack;

    return BlocBuilder<CryptoTopupBloc, CryptoTopupState>(
      builder: (context, state) {
        return TurboTopupScaffold(
          title: 'Connect wallet',
          description:
              'Connect your ${widget.token.walletType.displayName} to complete the purchase.',
          canClose: widget.onCancel != null,
          onClose: widget.onCancel,
          actions: onBack == null
              ? null
              : [ModalAction.dismiss(title: 'Back', action: onBack)],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Payment summary card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.containerRaised,
                  borderRadius: BorderRadius.circular(ArDriveRadius.lg),
                  border: Border.all(color: colors.strokeMid),
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
                              color: colors.textHigh,
                            ),
                          ),
                          Text(
                            widget.token.networkDisplayName,
                            style: typography.paragraphSmall(
                              color: colors.textMid,
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
            ],
          ),
        );
      },
    );
  }

  Widget _buildConnectionContent(BuildContext context, CryptoTopupState state) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final bloc = context.read<CryptoTopupBloc>();

    // Wallet not installed
    if (state is CryptoTopupWalletNotInstalled) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ArDriveNotice(
            type: ArDriveNoticeType.warning,
            message:
                '${widget.token.walletType.displayName} not detected. Please install it to continue.',
          ),
          const SizedBox(height: 16),
          ArDriveButtonNew(
            typography: ArDriveTypographyNew.of(context),
            variant: ButtonVariant.primary,
            size: ArDriveButtonSize.large,
            maxWidth: double.infinity,
            text: 'Install ${_getWalletAppName()}',
            onPressed: () => _openInstallUrl(widget.token.walletType),
          ),
        ],
      );
    }

    // AO Connect signature needed
    if (state is CryptoTopupAOConnectSignature) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.containerRaised,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.strokeMid),
        ),
        child: Row(
          children: [
            const ArDriveSpinner(),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Please sign the message in your Ethereum wallet to continue.',
                style: typography.paragraphNormal(
                  color: colors.textHigh,
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ArDriveNotice(
            type: ArDriveNoticeType.info,
            message:
                'Please switch to ${widget.token.networkDisplayName} in your wallet.',
          ),
          const SizedBox(height: 16),
          ArDriveButtonNew(
            typography: ArDriveTypographyNew.of(context),
            variant: ButtonVariant.primary,
            size: ArDriveButtonSize.large,
            maxWidth: double.infinity,
            text: 'Switch network',
            onPressed: () {
              final chainId =
                  bloc.networkConfig.getChainIdForToken(widget.token);
              if (chainId != null) {
                bloc.add(CryptoTopupSwitchNetwork(chainId));
              }
            },
          ),
        ],
      );
    }

    // Connecting
    if (state is CryptoTopupWalletConnection && state.isConnecting) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.containerRaised,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.strokeMid),
        ),
        child: Row(
          children: [
            const ArDriveSpinner(),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Connecting to ${widget.token.walletType.displayName}...',
                style: typography.paragraphNormal(
                  color: colors.textHigh,
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
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
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
            'Select wallet',
            style: typography.paragraphNormal(
              fontWeight: ArFontWeight.semiBold,
              color: colors.textHigh,
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
            ethereumProvider: EthereumWalletProvider
                .metamask, // Brave uses MetaMask interface
          )),
        ));
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select wallet',
            style: typography.paragraphNormal(
              fontWeight: ArFontWeight.semiBold,
              color: colors.textHigh,
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
            'Select wallet',
            style: typography.paragraphNormal(
              fontWeight: ArFontWeight.semiBold,
              color: colors.textHigh,
            ),
          ),
          const SizedBox(height: 12),
          ...walletButtons,
        ],
      );
    }

    // Fallback: generic connect button
    return ArDriveButtonNew(
      typography: ArDriveTypographyNew.of(context),
      variant: ButtonVariant.primary,
      size: ArDriveButtonSize.large,
      maxWidth: double.infinity,
      text: 'Connect ${_getWalletAppName()}',
      onPressed: () => bloc.add(const CryptoTopupConnectWallet()),
    );
  }

  /// Build message when no wallets are detected
  Widget _buildNoWalletsDetected(
    BuildContext context,
    ArDriveColorTokens colors,
    ArdriveTypographyNew typography,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ArDriveNotice(
          type: ArDriveNoticeType.warning,
          title: 'No wallets detected',
          message: _getInstallInstructions(),
        ),
        const SizedBox(height: 16),
        ArDriveButtonNew(
          typography: ArDriveTypographyNew.of(context),
          variant: ButtonVariant.primary,
          size: ArDriveButtonSize.large,
          maxWidth: double.infinity,
          text: 'Install ${_getWalletAppName()}',
          onPressed: () => _openInstallUrl(widget.token.walletType),
        ),
      ],
    );
  }

  String _getInstallInstructions() {
    return switch (widget.token.walletType) {
      WalletType.ethereum =>
        'Please install a wallet extension like MetaMask or Coinbase Wallet to continue.',
      WalletType.solana => 'Please install Phantom or Solflare to continue.',
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
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: colors.containerRaised,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.strokeMid),
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
                  color: colors.textHigh,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: colors.textMid,
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
        // White on the token's own brand colour, below.
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Color(0xFFFFFFFF),
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

  // The tokens' own brand colours.
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
