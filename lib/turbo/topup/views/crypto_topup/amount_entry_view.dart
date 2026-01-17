import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/views/crypto_topup/components/components.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Amount entry view - user enters payment amount.
class AmountEntryView extends StatelessWidget {
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  const AmountEntryView({
    super.key,
    this.onBack,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CryptoTopupBloc, CryptoTopupState>(
      buildWhen: (previous, current) => current is CryptoTopupAmountEntry,
      builder: (context, state) {
        if (state is! CryptoTopupAmountEntry) {
          return const SizedBox.shrink();
        }

        return _AmountEntryContent(
          state: state,
          onBack: onBack,
          onClose: onClose,
        );
      },
    );
  }
}

class _AmountEntryContent extends StatelessWidget {
  final CryptoTopupAmountEntry state;
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  const _AmountEntryContent({
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
                  'Enter Amount',
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

          // Wallet address
          _WalletAddressDisplay(address: state.walletAddress),
          const SizedBox(height: 16),

          // Network warning banner (if on wrong network)
          if (state.balance.isNetworkError) ...[
            _NetworkSwitchBanner(
              token: state.token,
              onSwitch: () {
                final chainId = state.token.chainId;
                if (chainId != null) {
                  bloc.add(CryptoTopupSwitchNetwork(chainId));
                }
              },
            ),
            const SizedBox(height: 16),
          ],

          // Amount input
          CryptoAmountInput(
            token: state.token,
            isUsdMode: state.isUsdMode,
            currentAmount: state.currentAmount,
            balance: state.balance,
            error: _getAmountError(state),
            onAmountChanged: (amount) {
              bloc.add(CryptoTopupUpdateAmount(amount));
            },
            onToggleMode: () {
              bloc.add(const CryptoTopupToggleAmountMode());
            },
          ),
          const SizedBox(height: 16),

          // Preset amounts
          if (state.isUsdMode)
            PresetAmountButtons(
              amounts: const [10, 25, 50, 100],
              selectedAmount: state.currentAmount,
              isUsdMode: state.isUsdMode,
              onAmountSelected: (amount) {
                bloc.add(CryptoTopupUpdateAmount(amount));
              },
            ),
          const SizedBox(height: 24),

          // Quote display
          if (state.isLoadingQuote)
            const QuoteLoadingPlaceholder()
          else if (state.quote != null)
            QuoteDisplay(
              quote: state.quote!,
              expiresAt: state.quoteExpiresAt,
              onRefresh: () {
                bloc.add(const CryptoTopupRefreshQuote());
              },
            ),
          const SizedBox(height: 16),

          // Promo code
          PromoCodeInput(
            currentCode: state.promoCode,
            isValidating: state.promoCodeState == PromoCodeState.validating,
            isValid: state.promoCodeState == PromoCodeState.valid,
            error: state.promoError,
            onCodeSubmitted: (code) {
              bloc.add(CryptoTopupApplyPromoCode(code));
            },
            onClear: () {
              bloc.add(const CryptoTopupRemovePromoCode());
            },
          ),
          const SizedBox(height: 24),

          // Error message
          if (state.error != null) ...[
            _ErrorMessage(message: state.error!),
            const SizedBox(height: 16),
          ],

          // Continue button
          SizedBox(
            width: double.infinity,
            child: ArDriveButton(
              text: 'Continue',
              onPressed: _canContinue(state)
                  ? () => bloc.add(const CryptoTopupProceedToConfirmation())
                  : null,
              isDisabled: !_canContinue(state),
            ),
          ),
        ],
      ),
    );
  }

  String? _getAmountError(CryptoTopupAmountEntry state) {
    if (state.quote != null && !state.hasSufficientBalance) {
      return 'Insufficient balance';
    }
    return null;
  }

  bool _canContinue(CryptoTopupAmountEntry state) {
    return state.quote != null &&
        !state.isLoadingQuote &&
        state.hasSufficientBalance &&
        state.currentAmount > 0;
  }
}

class _WalletAddressDisplay extends StatelessWidget {
  final String address;

  const _WalletAddressDisplay({required this.address});

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: colorTokens.textHigh,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Connected: ${_truncateAddress(address)}',
          style: typography.paragraphSmall(
            color: colorTokens.textMid,
          ),
        ),
      ],
    );
  }

  String _truncateAddress(String address) {
    if (address.length < 10) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
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

class _NetworkSwitchBanner extends StatelessWidget {
  final CryptoToken token;
  final VoidCallback onSwitch;

  const _NetworkSwitchBanner({
    required this.token,
    required this.onSwitch,
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
            Icons.swap_horiz,
            color: colorTokens.textMid,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Switch to ${token.networkDisplayName} to continue',
              style: typography.paragraphSmall(
                color: colorTokens.textMid,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onSwitch,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colorTokens.containerL2,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Switch',
                style: typography.paragraphSmall(
                  fontWeight: ArFontWeight.semiBold,
                  color: colorTokens.textHigh,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
