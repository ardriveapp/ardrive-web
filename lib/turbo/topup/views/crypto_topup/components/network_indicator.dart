import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// Chain ID to network name mapping
String getNetworkName(int chainId) {
  switch (chainId) {
    case 1:
      return 'Ethereum Mainnet';
    case 8453:
      return 'Base';
    case 11155111:
      return 'Sepolia (Testnet)';
    case 84532:
      return 'Base Sepolia (Testnet)';
    default:
      return 'Unknown Network';
  }
}

/// Get network icon color
/// Note: These are brand colors that should remain consistent across themes.
/// Ethereum blue and Base blue are recognizable brand identifiers.
Color getNetworkColor(int chainId, {Color? fallbackColor}) {
  switch (chainId) {
    case 1:
    case 11155111:
      return const Color(0xFF627EEA); // Ethereum brand blue
    case 8453:
    case 84532:
      return const Color(0xFF0052FF); // Base brand blue
    default:
      return fallbackColor ?? const Color(0xFF9CA3AF); // Neutral gray
  }
}

/// Displays the current network status for EVM wallets.
class NetworkIndicator extends StatelessWidget {
  final int currentChainId;
  final int? requiredChainId;
  final bool isCorrectNetwork;
  final bool isSwitching;
  final VoidCallback? onSwitchNetwork;

  const NetworkIndicator({
    super.key,
    required this.currentChainId,
    this.requiredChainId,
    this.isCorrectNetwork = true,
    this.isSwitching = false,
    this.onSwitchNetwork,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isCorrectNetwork
            ? colorTokens.containerL1
            : colorTokens.containerL1,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCorrectNetwork
              ? colorTokens.strokeLow
              : colorTokens.strokeLow,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Network indicator dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isCorrectNetwork
                  ? getNetworkColor(currentChainId, fallbackColor: colorTokens.textMid)
                  : colorTokens.textLow,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          // Network name
          Text(
            getNetworkName(currentChainId),
            style: typography.paragraphSmall(
              color: colorTokens.textMid,
            ),
          ),
          // Switch button if wrong network
          if (!isCorrectNetwork && onSwitchNetwork != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: isSwitching ? null : onSwitchNetwork,
              child: isSwitching
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorTokens.textMid,
                      ),
                    )
                  : Text(
                      'Switch',
                      style: typography.paragraphSmall(
                        fontWeight: ArFontWeight.semiBold,
                        color: colorTokens.textHigh,
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Warning banner when on wrong network
class NetworkWarningBanner extends StatelessWidget {
  final int currentChainId;
  final int requiredChainId;
  final bool isSwitching;
  final VoidCallback? onSwitchNetwork;
  final VoidCallback? onShowManualInstructions;

  const NetworkWarningBanner({
    super.key,
    required this.currentChainId,
    required this.requiredChainId,
    this.isSwitching = false,
    this.onSwitchNetwork,
    this.onShowManualInstructions,
  });

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
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: colorTokens.textMid,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Wrong Network',
                style: typography.paragraphNormal(
                  fontWeight: ArFontWeight.semiBold,
                  color: colorTokens.textHigh,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Your wallet is connected to ${getNetworkName(currentChainId)}. '
            'Please switch to ${getNetworkName(requiredChainId)} to continue.',
            style: typography.paragraphSmall(
              color: colorTokens.textMid,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ArDriveButton(
                  text: isSwitching ? 'Switching...' : 'Switch Network',
                  onPressed: isSwitching ? () {} : onSwitchNetwork,
                  isDisabled: isSwitching,
                ),
              ),
              if (onShowManualInstructions != null) ...[
                const SizedBox(width: 8),
                ArDriveButton(
                  text: 'Manual',
                  style: ArDriveButtonStyle.secondary,
                  onPressed: onShowManualInstructions,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Manual network switch instructions
class ManualNetworkSwitchInstructions extends StatelessWidget {
  final CryptoToken token;

  const ManualNetworkSwitchInstructions({
    super.key,
    required this.token,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    final chainId = token.chainId;
    final networkName = chainId != null ? getNetworkName(chainId) : 'Unknown';

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
            'Manual Network Switch',
            style: typography.paragraphLarge(
              fontWeight: ArFontWeight.semiBold,
              color: colorTokens.textHigh,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'To add $networkName to your wallet:',
            style: typography.paragraphNormal(
              color: colorTokens.textMid,
            ),
          ),
          const SizedBox(height: 8),
          const _InstructionStep(
            number: 1,
            text: 'Open your wallet extension',
          ),
          const _InstructionStep(
            number: 2,
            text: 'Click on the network selector',
          ),
          const _InstructionStep(
            number: 3,
            text: 'Select "Add Network" or "Custom RPC"',
          ),
          const _InstructionStep(
            number: 4,
            text: 'Enter the network details below',
          ),
          const SizedBox(height: 12),
          _NetworkDetails(token: token),
        ],
      ),
    );
  }
}

class _InstructionStep extends StatelessWidget {
  final int number;
  final String text;

  const _InstructionStep({
    required this.number,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: colorTokens.containerL2,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number.toString(),
                style: typography.paragraphSmall(
                  fontWeight: ArFontWeight.bold,
                  color: colorTokens.textMid,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
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

class _NetworkDetails extends StatelessWidget {
  final CryptoToken token;

  const _NetworkDetails({required this.token});

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    final chainId = token.chainId;
    if (chainId == null) return const SizedBox.shrink();

    final details = _getNetworkDetails(chainId);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorTokens.containerL2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: details.entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 100,
                  child: Text(
                    entry.key,
                    style: typography.paragraphSmall(
                      color: colorTokens.textMid,
                    ),
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    entry.value,
                    style: typography.paragraphSmall(
                      fontWeight: ArFontWeight.semiBold,
                      color: colorTokens.textHigh,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Map<String, String> _getNetworkDetails(int chainId) {
    switch (chainId) {
      case 8453:
        return {
          'Network Name': 'Base',
          'RPC URL': 'https://mainnet.base.org',
          'Chain ID': '8453',
          'Currency': 'ETH',
          'Explorer': 'https://basescan.org',
        };
      case 1:
        return {
          'Network Name': 'Ethereum Mainnet',
          'RPC URL': 'https://eth.llamarpc.com',
          'Chain ID': '1',
          'Currency': 'ETH',
          'Explorer': 'https://etherscan.io',
        };
      default:
        return {
          'Chain ID': chainId.toString(),
        };
    }
  }
}
