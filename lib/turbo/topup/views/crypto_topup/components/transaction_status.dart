import 'package:ardrive/turbo/config/crypto_network_config.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Transaction status for display
enum TransactionDisplayStatus {
  submitting,
  pending,
  confirming,
  success,
  failed,
}

extension TransactionDisplayStatusExtension on TransactionDisplayStatus {
  String get displayText {
    switch (this) {
      case TransactionDisplayStatus.submitting:
        return 'Submitting transaction...';
      case TransactionDisplayStatus.pending:
        return 'Transaction pending';
      case TransactionDisplayStatus.confirming:
        return 'Confirming on blockchain...';
      case TransactionDisplayStatus.success:
        return 'Transaction confirmed';
      case TransactionDisplayStatus.failed:
        return 'Transaction failed';
    }
  }

  IconData get icon {
    switch (this) {
      case TransactionDisplayStatus.submitting:
      case TransactionDisplayStatus.pending:
      case TransactionDisplayStatus.confirming:
        return Icons.hourglass_top;
      case TransactionDisplayStatus.success:
        return Icons.check_circle;
      case TransactionDisplayStatus.failed:
        return Icons.error;
    }
  }

  bool get isLoading {
    switch (this) {
      case TransactionDisplayStatus.submitting:
      case TransactionDisplayStatus.pending:
      case TransactionDisplayStatus.confirming:
        return true;
      case TransactionDisplayStatus.success:
      case TransactionDisplayStatus.failed:
        return false;
    }
  }
}

/// Displays transaction processing status.
class TransactionStatusDisplay extends StatelessWidget {
  final TransactionDisplayStatus status;
  final String? txId;
  final CryptoToken token;
  final String? message;
  final CryptoNetworkConfig? networkConfig;

  const TransactionStatusDisplay({
    super.key,
    required this.status,
    this.txId,
    required this.token,
    this.message,
    this.networkConfig,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Status icon/spinner
          _StatusIndicator(status: status),
          const SizedBox(height: 16),

          // Status text
          Text(
            status.displayText,
            style: typography.heading5(
              fontWeight: ArFontWeight.semiBold,
              color: colorTokens.textHigh,
            ),
            textAlign: TextAlign.center,
          ),

          // Additional message
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              style: typography.paragraphSmall(
                color: colorTokens.textMid,
              ),
              textAlign: TextAlign.center,
            ),
          ],

          // Transaction link
          if (txId != null) ...[
            const SizedBox(height: 16),
            _TransactionLink(
              txId: txId!,
              token: token,
              networkConfig: networkConfig,
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  final TransactionDisplayStatus status;

  const _StatusIndicator({required this.status});

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    if (status.isLoading) {
      return SizedBox(
        width: 60,
        height: 60,
        child: CircularProgressIndicator(
          strokeWidth: 4,
          color: colorTokens.textHigh,
        ),
      );
    }

    final iconColor = status == TransactionDisplayStatus.success
        ? colorTokens.textHigh
        : colorTokens.textLow;

    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: colorTokens.containerL2,
        shape: BoxShape.circle,
      ),
      child: Icon(
        status.icon,
        size: 32,
        color: iconColor,
      ),
    );
  }
}

class _TransactionLink extends StatelessWidget {
  final String txId;
  final CryptoToken token;
  final CryptoNetworkConfig? networkConfig;

  const _TransactionLink({
    required this.txId,
    required this.token,
    this.networkConfig,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    final explorerUrl = _getExplorerUrl(txId, token);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Truncated tx ID
        Text(
          'TX: ${_truncateTxId(txId)}',
          style: typography.paragraphSmall(
            color: colorTokens.textMid,
          ),
        ),
        const SizedBox(width: 8),
        // Copy button
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: txId));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Transaction ID copied'),
                duration: Duration(seconds: 2),
              ),
            );
          },
          child: Icon(
            Icons.copy,
            size: 14,
            color: colorTokens.textMid,
          ),
        ),
        // Explorer link
        if (explorerUrl != null) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _openExplorer(explorerUrl),
            child: Icon(
              Icons.open_in_new,
              size: 14,
              color: colorTokens.textMid,
            ),
          ),
        ],
      ],
    );
  }

  String _truncateTxId(String txId) {
    if (txId.length < 16) return txId;
    return '${txId.substring(0, 8)}...${txId.substring(txId.length - 8)}';
  }

  String? _getExplorerUrl(String txId, CryptoToken token) {
    // Use environment-aware config if available
    if (networkConfig != null) {
      return networkConfig!.getExplorerTxUrl(token, txId);
    }

    // Fallback to hardcoded mainnet URLs if no config provided
    switch (token.blockchain) {
      case Blockchain.ethereum:
        return 'https://etherscan.io/tx/$txId';
      case Blockchain.base:
        return 'https://basescan.org/tx/$txId';
      case Blockchain.solana:
        return 'https://solscan.io/tx/$txId';
      case Blockchain.ao:
        return 'https://scan.ar.io/#/message/$txId';
    }
  }

  Future<void> _openExplorer(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

/// Success view with confetti or celebration
class TransactionSuccessView extends StatelessWidget {
  final String txId;
  final String creditsAdded;
  final String? newBalance;
  final CryptoToken token;
  final VoidCallback? onDone;
  final CryptoNetworkConfig? networkConfig;

  const TransactionSuccessView({
    super.key,
    required this.txId,
    required this.creditsAdded,
    this.newBalance,
    required this.token,
    this.onDone,
    this.networkConfig,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Success icon
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: colorTokens.containerL2,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_circle,
              size: 48,
              color: colorTokens.textHigh,
            ),
          ),
          const SizedBox(height: 24),

          // Success message
          Text(
            'Payment Successful!',
            style: typography.heading4(
              fontWeight: ArFontWeight.bold,
              color: colorTokens.textHigh,
            ),
          ),
          const SizedBox(height: 8),

          // Credits added
          Text(
            '$creditsAdded added to your account',
            style: typography.paragraphNormal(
              color: colorTokens.textMid,
            ),
          ),

          // New balance
          if (newBalance != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: colorTokens.containerL1,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'New Balance: ',
                    style: typography.paragraphSmall(
                      color: colorTokens.textMid,
                    ),
                  ),
                  Text(
                    newBalance!,
                    style: typography.paragraphNormal(
                      fontWeight: ArFontWeight.semiBold,
                      color: colorTokens.textHigh,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Transaction link
          _TransactionLink(
            txId: txId,
            token: token,
            networkConfig: networkConfig,
          ),
          const SizedBox(height: 24),

          // Done button
          if (onDone != null)
            SizedBox(
              width: double.infinity,
              child: ArDriveButton(
                text: 'Done',
                onPressed: onDone,
              ),
            ),
        ],
      ),
    );
  }
}

/// Error view with retry option
class TransactionErrorView extends StatelessWidget {
  final String errorMessage;
  final String? txId;
  final CryptoToken? token;
  final bool canRetry;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;
  final CryptoNetworkConfig? networkConfig;

  const TransactionErrorView({
    super.key,
    required this.errorMessage,
    this.txId,
    this.token,
    this.canRetry = true,
    this.onRetry,
    this.onCancel,
    this.networkConfig,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Error icon
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: ArDriveTheme.of(context).themeData.colors.themeErrorSubtle,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.error_outline,
              size: 48,
              color:
                  ArDriveTheme.of(context).themeData.colors.themeErrorDefault,
            ),
          ),
          const SizedBox(height: 24),

          // Error title
          Text(
            'Payment Failed',
            style: typography.heading4(
              fontWeight: ArFontWeight.bold,
              color: colorTokens.textHigh,
            ),
          ),
          const SizedBox(height: 8),

          // Error message
          Text(
            errorMessage,
            style: typography.paragraphNormal(
              color: colorTokens.textMid,
            ),
            textAlign: TextAlign.center,
          ),

          // Transaction link if available
          if (txId != null && token != null) ...[
            const SizedBox(height: 16),
            _TransactionLink(
              txId: txId!,
              token: token!,
              networkConfig: networkConfig,
            ),
          ],
          const SizedBox(height: 24),

          // Action buttons
          Row(
            children: [
              if (onCancel != null)
                Expanded(
                  child: ArDriveButton(
                    text: 'Cancel',
                    style: ArDriveButtonStyle.secondary,
                    onPressed: onCancel,
                  ),
                ),
              if (onCancel != null && canRetry && onRetry != null)
                const SizedBox(width: 12),
              if (canRetry && onRetry != null)
                Expanded(
                  child: ArDriveButton(
                    text: 'Try Again',
                    onPressed: onRetry,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
