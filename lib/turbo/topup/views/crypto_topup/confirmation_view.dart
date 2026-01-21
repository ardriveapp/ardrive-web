import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/views/crypto_topup/components/components.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Confirmation view - final review before payment.
class ConfirmationView extends StatelessWidget {
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  const ConfirmationView({
    super.key,
    this.onBack,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CryptoTopupBloc, CryptoTopupState>(
      buildWhen: (previous, current) => current is CryptoTopupConfirmation,
      builder: (context, state) {
        if (state is! CryptoTopupConfirmation) {
          return const SizedBox.shrink();
        }

        return _ConfirmationContent(
          state: state,
          onBack: onBack,
          onClose: onClose,
        );
      },
    );
  }
}

class _ConfirmationContent extends StatefulWidget {
  final CryptoTopupConfirmation state;
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  const _ConfirmationContent({
    required this.state,
    this.onBack,
    this.onClose,
  });

  @override
  State<_ConfirmationContent> createState() => _ConfirmationContentState();
}

class _ConfirmationContentState extends State<_ConfirmationContent> {
  bool _termsAccepted = false;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final bloc = context.read<CryptoTopupBloc>();
    final state = widget.state;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with back button
          Row(
            children: [
              if (widget.onBack != null && !state.isProcessing)
                GestureDetector(
                  onTap: widget.onBack,
                  child: Icon(
                    Icons.arrow_back,
                    color: colorTokens.textMid,
                    size: 24,
                  ),
                ),
              if (widget.onBack != null) const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Confirm Payment',
                  style: typography.heading4(
                    fontWeight: ArFontWeight.bold,
                    color: colorTokens.textHigh,
                  ),
                ),
              ),
              if (widget.onClose != null && !state.isProcessing)
                GestureDetector(
                  onTap: widget.onClose,
                  child: Icon(
                    Icons.close,
                    color: colorTokens.textMid,
                    size: 24,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),

          // Network status
          if (state.token.chainId != null) ...[
            _NetworkStatusSection(state: state, bloc: bloc),
            const SizedBox(height: 24),
          ],

          // Payment summary
          _PaymentSummary(state: state),
          const SizedBox(height: 24),

          // Transaction details
          _TransactionDetails(state: state),
          const SizedBox(height: 24),

          // Promo code applied
          if (state.promoCode != null) ...[
            _PromoCodeApplied(code: state.promoCode!),
            const SizedBox(height: 24),
          ],

          // Network error
          if (state.networkError != null) ...[
            _ErrorMessage(message: state.networkError!),
            const SizedBox(height: 16),
          ],

          // Terms acceptance checkbox
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: _termsAccepted,
                  onChanged: state.isProcessing
                      ? null
                      : (value) {
                          setState(() {
                            _termsAccepted = value ?? false;
                          });
                        },
                  activeColor: colorTokens.textHigh,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: state.isProcessing
                      ? null
                      : () {
                          setState(() {
                            _termsAccepted = !_termsAccepted;
                          });
                        },
                  child: Text(
                    'I agree to the terms of service',
                    style: typography.paragraphSmall(
                      color: colorTokens.textMid,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Confirm button
          SizedBox(
            width: double.infinity,
            child: ArDriveButton(
              text: state.isProcessing ? 'Processing...' : 'Confirm & Pay',
              onPressed: state.canConfirm && _termsAccepted
                  ? () => bloc.add(const CryptoTopupConfirmPayment())
                  : null,
              isDisabled: !state.canConfirm || !_termsAccepted || state.isProcessing,
            ),
          ),
        ],
      ),
    );
  }
}

class _NetworkStatusSection extends StatelessWidget {
  final CryptoTopupConfirmation state;
  final CryptoTopupBloc bloc;

  const _NetworkStatusSection({
    required this.state,
    required this.bloc,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    // Determine current chain ID (would come from wallet cubit in real impl)
    final requiredChainId = state.token.chainId!;

    switch (state.networkState) {
      case NetworkState.checking:
        return _buildStatusRow(
          context,
          Icons.hourglass_top,
          'Checking network...',
          colorTokens.textMid,
        );

      case NetworkState.correct:
        return _buildStatusRow(
          context,
          Icons.check_circle,
          'Connected to ${getNetworkName(requiredChainId)}',
          colorTokens.textHigh,
        );

      case NetworkState.switching:
        return _buildStatusRow(
          context,
          Icons.sync,
          'Switching network...',
          colorTokens.textMid,
        );

      case NetworkState.needsSwitch:
      case NetworkState.needsAdd:
      case NetworkState.switchFailed:
        return NetworkWarningBanner(
          currentChainId: state.currentChainId ?? 1,
          requiredChainId: requiredChainId,
          isSwitching: state.networkState == NetworkState.switching,
          onSwitchNetwork: () {
            bloc.add(CryptoTopupSwitchNetwork(requiredChainId));
          },
          onShowManualInstructions: () {
            bloc.add(const CryptoTopupShowManualNetworkSwitch());
          },
        );
    }
  }

  Widget _buildStatusRow(
    BuildContext context,
    IconData icon,
    String text,
    Color color,
  ) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorTokens.containerL1,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            text,
            style: typography.paragraphSmall(color: color),
          ),
        ],
      ),
    );
  }
}

class _PaymentSummary extends StatelessWidget {
  final CryptoTopupConfirmation state;

  const _PaymentSummary({required this.state});

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
        children: [
          // You pay
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'You pay',
                style: typography.paragraphNormal(
                  color: colorTokens.textMid,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    state.quote.formattedTokenAmount,
                    style: typography.heading5(
                      fontWeight: ArFontWeight.bold,
                      color: colorTokens.textHigh,
                    ),
                  ),
                  Text(
                    '\$${state.quote.usdValue.toStringAsFixed(2)}',
                    style: typography.paragraphSmall(
                      color: colorTokens.textMid,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: colorTokens.strokeLow, height: 1),
          const SizedBox(height: 16),
          // You receive
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'You receive',
                style: typography.paragraphNormal(
                  color: colorTokens.textMid,
                ),
              ),
              Text(
                state.quote.formattedCredits,
                style: typography.heading5(
                  fontWeight: ArFontWeight.bold,
                  color: colorTokens.textHigh,
                ),
              ),
            ],
          ),
          // Gas estimate
          if (state.gasEstimateUsd != null) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Est. gas fee',
                  style: typography.paragraphSmall(
                    color: colorTokens.textMid,
                  ),
                ),
                Text(
                  '\$${state.gasEstimateUsd!.toStringAsFixed(2)}',
                  style: typography.paragraphSmall(
                    color: colorTokens.textMid,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TransactionDetails extends StatelessWidget {
  final CryptoTopupConfirmation state;

  const _TransactionDetails({required this.state});

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorTokens.containerL1,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Transaction Details',
            style: typography.paragraphNormal(
              fontWeight: ArFontWeight.semiBold,
              color: colorTokens.textHigh,
            ),
          ),
          const SizedBox(height: 12),
          _DetailRow(
            label: 'From',
            value: _truncateAddress(state.fromAddress),
          ),
          const SizedBox(height: 8),
          _DetailRow(
            label: 'To',
            value: _truncateAddress(state.toAddress),
          ),
          const SizedBox(height: 8),
          _DetailRow(
            label: 'Network',
            value: state.token.networkDisplayName,
          ),
        ],
      ),
    );
  }

  String _truncateAddress(String address) {
    if (address.length < 16) return address;
    return '${address.substring(0, 8)}...${address.substring(address.length - 8)}';
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: typography.paragraphSmall(
            color: colorTokens.textMid,
          ),
        ),
        SelectableText(
          value,
          style: typography.paragraphSmall(
            fontWeight: ArFontWeight.semiBold,
            color: colorTokens.textHigh,
          ),
        ),
      ],
    );
  }
}

class _PromoCodeApplied extends StatelessWidget {
  final String code;

  const _PromoCodeApplied({required this.code});

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorTokens.containerL1,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.local_offer,
            size: 14,
            color: colorTokens.textHigh,
          ),
          const SizedBox(width: 4),
          Text(
            'Promo code applied: $code',
            style: typography.paragraphSmall(
              color: colorTokens.textMid,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  final String message;

  const _ErrorMessage({required this.message});

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
            Icons.error_outline,
            color: colorTokens.textLow,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
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
