import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive/turbo/topup/models/crypto_quote.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Streamlined crypto payment confirmation view.
///
/// Shows a summary of the payment and a confirm button.
/// This replaces the previous multi-step confirmation flow.
class CryptoConfirmationView extends StatelessWidget {
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  const CryptoConfirmationView({
    super.key,
    this.onBack,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final themeData = ArDriveTheme.of(context).themeData;
    final colors = themeData.colors;
    final colorTokens = themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return BlocBuilder<CryptoTopupBloc, CryptoTopupState>(
      builder: (context, state) {
        if (state is! CryptoTopupConfirmation) {
          return const Center(child: CircularProgressIndicator());
        }

        final bloc = context.read<CryptoTopupBloc>();

        return Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
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
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 24), // Space for close button
                          // Header (title only, no back button)
                          Text(
                            'Confirm Payment',
                            style: typography.heading5(
                              fontWeight: ArFontWeight.bold,
                              color: colors.themeFgDefault,
                            ),
                          ),
                          const SizedBox(height: 32),

                          // Payment summary card
                          _PaymentSummaryCard(
                            quote: state.quote,
                            fromAddress: state.fromAddress,
                            token: state.token,
                          ),
                          const SizedBox(height: 24),

                          // Network status (for EVM tokens)
                          if (state.token.requiresGasEstimation) ...[
                            _NetworkStatusBanner(
                              networkState: state.networkState,
                              token: state.token,
                              onSwitchNetwork: () {
                                final chainId = state.token.chainId;
                                if (chainId != null) {
                                  bloc.add(CryptoTopupSwitchNetwork(chainId));
                                }
                              },
                            ),
                            const SizedBox(height: 24),
                          ],

                          // Quote timer
                          _QuoteTimer(expiresAt: state.quote.expiresAt),
                          const SizedBox(height: 24),

                          // Terms notice
                          Text(
                            'By confirming, you agree to the Terms of Service. '
                            'This transaction cannot be reversed once confirmed.',
                            style: typography.paragraphSmall(
                              color: colors.themeFgMuted,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Footer with back button on left and confirm button on right
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
                      SizedBox(
                        height: 48,
                        child: ArDriveButton(
                          isDisabled:
                              state.networkState == NetworkState.needsSwitch ||
                                  state.networkState == NetworkState.switching,
                          text: _getButtonText(state),
                          onPressed: () {
                            bloc.add(const CryptoTopupConfirmPayment());
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Close button in top right
            if (onClose != null)
              Positioned(
                right: 27,
                top: 27,
                child: ArDriveClickArea(
                  child: GestureDetector(
                    onTap: onClose,
                    child: ArDriveIcons.x(),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  String _getButtonText(CryptoTopupConfirmation state) {
    if (state.networkState == NetworkState.switching) {
      return 'Switching Network...';
    }
    if (state.networkState == NetworkState.needsSwitch) {
      return 'Switch Network First';
    }
    return 'Confirm & Pay ${state.quote.formattedTokenAmount}';
  }
}

class _PaymentSummaryCard extends StatelessWidget {
  final CryptoQuote quote;
  final String fromAddress;
  final CryptoToken token;

  const _PaymentSummaryCard({
    required this.quote,
    required this.fromAddress,
    required this.token,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.themeBgSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.themeBorderDefault),
      ),
      child: Column(
        children: [
          // You're buying
          _SummaryRow(
            label: "You're buying",
            value: quote.formattedCredits,
            typography: typography,
            colors: colors,
            isLarge: true,
          ),
          const SizedBox(height: 16),
          Divider(color: colors.themeBorderDefault, height: 1),
          const SizedBox(height: 16),

          // You pay
          _SummaryRow(
            label: 'You pay',
            value: quote.formattedTokenAmount,
            typography: typography,
            colors: colors,
          ),
          const SizedBox(height: 12),

          // Network fee (if applicable)
          if (token.requiresGasEstimation) ...[
            _SummaryRow(
              label: 'Est. network fee',
              value: '~\$2-5',
              typography: typography,
              colors: colors,
              isMuted: true,
            ),
            const SizedBox(height: 12),
          ],

          // From wallet
          _SummaryRow(
            label: 'From',
            value: _truncateAddress(fromAddress),
            typography: typography,
            colors: colors,
            isMuted: true,
          ),
          const SizedBox(height: 12),

          // To
          _SummaryRow(
            label: 'To',
            value: 'Turbo Credits Gateway',
            typography: typography,
            colors: colors,
            isMuted: true,
          ),
        ],
      ),
    );
  }

  String _truncateAddress(String address) {
    if (address.length < 12) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final ArdriveTypographyNew typography;
  final ArDriveColors colors;
  final bool isLarge;
  final bool isMuted;

  const _SummaryRow({
    required this.label,
    required this.value,
    required this.typography,
    required this.colors,
    this.isLarge = false,
    this.isMuted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: isLarge
              ? typography.paragraphLarge(color: colors.themeFgDefault)
              : typography.paragraphNormal(
                  color: isMuted ? colors.themeFgMuted : colors.themeFgDefault,
                ),
        ),
        Text(
          value,
          style: isLarge
              ? typography.paragraphLarge(
                  fontWeight: ArFontWeight.bold,
                  color: colors.themeFgDefault,
                )
              : typography.paragraphNormal(
                  fontWeight: isMuted ? ArFontWeight.book : ArFontWeight.semiBold,
                  color: isMuted ? colors.themeFgMuted : colors.themeFgDefault,
                ),
        ),
      ],
    );
  }
}

class _NetworkStatusBanner extends StatelessWidget {
  final NetworkState networkState;
  final CryptoToken token;
  final VoidCallback onSwitchNetwork;

  const _NetworkStatusBanner({
    required this.networkState,
    required this.token,
    required this.onSwitchNetwork,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    if (networkState == NetworkState.correct) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.themeBgSubtle,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.themeBorderDefault),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: colors.themeFgMuted, size: 20),
            const SizedBox(width: 8),
            Text(
              'Connected to ${token.networkDisplayName}',
              style: typography.paragraphSmall(
                color: colors.themeFgDefault,
              ),
            ),
          ],
        ),
      );
    }

    if (networkState == NetworkState.switching) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.themeBgSubtle,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.themeFgMuted,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Switching network...',
              style: typography.paragraphSmall(
                color: colors.themeFgMuted,
              ),
            ),
          ],
        ),
      );
    }

    // Needs switch
    return Container(
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
              'Please switch to ${token.networkDisplayName}',
              style: typography.paragraphSmall(
                color: colors.themeWarningFg,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onSwitchNetwork,
            child: Text(
              'Switch',
              style: typography.paragraphSmall(
                fontWeight: ArFontWeight.bold,
                color: colors.themeWarningFg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuoteTimer extends StatelessWidget {
  final DateTime? expiresAt;

  const _QuoteTimer({this.expiresAt});

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    if (expiresAt == null) return const SizedBox.shrink();

    return StreamBuilder(
      stream: Stream.periodic(const Duration(seconds: 1)),
      builder: (context, snapshot) {
        final remaining = expiresAt!.difference(DateTime.now());
        final isExpired = remaining.isNegative;
        final minutes = remaining.inMinutes;
        final seconds = remaining.inSeconds % 60;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isExpired ? colors.themeErrorSubtle : colors.themeBgSubtle,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.timer,
                size: 16,
                color: isExpired ? colors.themeErrorDefault : colors.themeFgMuted,
              ),
              const SizedBox(width: 8),
              Text(
                isExpired
                    ? 'Quote expired - please go back and refresh'
                    : 'Quote expires in ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                style: typography.paragraphSmall(
                  color: isExpired ? colors.themeErrorDefault : colors.themeFgMuted,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
