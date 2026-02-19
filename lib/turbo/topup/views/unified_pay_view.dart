import 'package:ardrive/turbo/topup/blocs/turbo_topup_flow_bloc.dart';
import 'package:ardrive/turbo/topup/blocs/unified_topup/unified_topup_bloc.dart';
import 'package:ardrive/turbo/topup/components/amount_mode_toggle.dart';
import 'package:ardrive/turbo/topup/components/fiat_preset_selector.dart';
import 'package:ardrive/turbo/topup/components/payment_method_selector.dart';
import 'package:ardrive/turbo/topup/components/purchase_summary.dart';
import 'package:ardrive/turbo/topup/components/storage_preset_selector.dart';
import 'package:ardrive/turbo/topup/components/turbo_topup_scaffold.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/views/turbo_error_view.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Unified pay view - the first page of the simplified topup flow.
///
/// This view combines payment method selection, amount selection,
/// and purchase summary into a single cohesive page.
class UnifiedPayView extends StatelessWidget {
  /// Callback when user is ready to continue to confirmation
  final void Function(PaymentMethod method, CryptoToken? token, double amount)
      onContinue;

  const UnifiedPayView({
    super.key,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<UnifiedTopupBloc, UnifiedTopupState>(
      listener: (context, state) {
        if (state is UnifiedTopupReadyToContinue) {
          // For crypto payments, pass the token amount directly
          // (crypto flow will use token-specific pricing for accurate rates)
          // For card payments, pass the fiat amount in USD
          onContinue(
            state.paymentMethod,
            state.selectedToken,
            state.fiatAmount, // Always pass the amount as entered
          );
        }
      },
      builder: (context, state) {
        if (state is UnifiedTopupInitial || state is UnifiedTopupLoading) {
          return const _LoadingView();
        }

        if (state is UnifiedTopupError) {
          return TurboErrorView(
            errorType: TurboErrorType.fetchEstimationInformationFailed,
            onDismiss: () {},
            onTryAgain: () {
              context.read<UnifiedTopupBloc>().add(const UnifiedTopupStarted());
            },
          );
        }

        if (state is UnifiedTopupLoaded) {
          return _LoadedView(state: state);
        }

        // For UnifiedTopupReadyToContinue, show the loaded view until navigation
        return const _LoadingView();
      },
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const TurboTopupScaffold(
      title: 'Buy Turbo Credits',
      child: SizedBox(
        height: 400,
        child: Center(
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}

class _LoadedView extends StatelessWidget {
  final UnifiedTopupLoaded state;

  const _LoadedView({required this.state});

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<UnifiedTopupBloc>();

    return SingleChildScrollView(
      child: TurboTopupScaffold(
        title: 'Buy Turbo Credits',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Payment method selector at top
            PaymentMethodSelector(
              selectedMethod: state.paymentMethod,
              selectedToken: state.selectedToken,
              onMethodChanged: (method) {
                bloc.add(UnifiedTopupPaymentMethodChanged(method: method));
              },
              onTokenSelected: (token) {
                bloc.add(UnifiedTopupPaymentMethodChanged(
                  method: PaymentMethod.crypto,
                  token: token,
                ));
              },
            ),
            const SizedBox(height: 16),

            // Amount mode toggle (Storage / Currency)
            AmountModeToggle(
              selectedMode: state.amountMode,
              currencyLabel: state.amountModeLabel,
              onModeChanged: (mode) {
                bloc.add(UnifiedTopupAmountModeChanged(mode));
              },
            ),
            const SizedBox(height: 16),

            // Amount selector (varies by mode)
            if (state.amountMode == AmountMode.storage)
              _StorageAmountSection(state: state, bloc: bloc)
            else
              _CurrencyAmountSection(state: state, bloc: bloc),

            const SizedBox(height: 16),

            // Promo code section
            _PromoCodeSection(state: state, bloc: bloc),

            const SizedBox(height: 16),

            // Purchase summary (simplified - balance shown on final checkout)
            if (state.fiatAmount > 0)
              PurchaseSummary(
                creditsToReceive: state.creditsToReceive,
                // estimatedStorage already includes the unit from formatStorageWithDynamicUnit
                storageEstimate: state.estimatedStorage,
                // Don't pass storageUnit since estimatedStorage already contains it
                priceAmount: state.fiatAmount,
                priceSymbol: state.priceSymbol,
                isPriceInToken: state.paymentMethod == PaymentMethod.crypto,
                usdEquivalent: state.usdEquivalent,
                hasPromoDiscount: state.discountPercent != null,
                discountPercent: state.discountPercent,
              )
            else
              const _EmptySummaryPlaceholder(),

            const SizedBox(height: 16),

            // Error message
            if (state.errorMessage != null)
              _ErrorMessage(message: state.errorMessage!),

            // Continue button
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ArDriveButton(
                isDisabled: !state.canContinue || state.isLoadingQuote,
                text: state.isLoadingQuote ? 'Loading...' : 'Continue',
                onPressed: () {
                  bloc.add(const UnifiedTopupContinuePressed());
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StorageAmountSection extends StatelessWidget {
  final UnifiedTopupLoaded state;
  final UnifiedTopupBloc bloc;

  const _StorageAmountSection({
    required this.state,
    required this.bloc,
  });

  @override
  Widget build(BuildContext context) {
    // Find matching preset
    StoragePreset? selectedPreset;
    if (state.storageSize != null) {
      for (final preset in defaultStoragePresets) {
        if (preset.value == state.storageSize &&
            preset.unit == state.storageUnit) {
          selectedPreset = preset;
          break;
        }
      }
    }

    return StoragePresetSelector(
      selectedPreset: selectedPreset,
      customValue: selectedPreset == null ? state.storageSize : null,
      customUnit: state.storageUnit,
      onPresetSelected: (preset) {
        bloc.add(UnifiedTopupStorageSizeSelected(
          size: preset.value,
          unit: preset.unit,
        ));
      },
      onCustomAmountChanged: (value, unit) {
        bloc.add(UnifiedTopupStorageSizeSelected(
          size: value,
          unit: unit,
        ));
      },
      onUnitChanged: (unit) {
        // Just update the unit, don't trigger new calculation yet
      },
    );
  }
}

class _CurrencyAmountSection extends StatelessWidget {
  final UnifiedTopupLoaded state;
  final UnifiedTopupBloc bloc;

  const _CurrencyAmountSection({
    required this.state,
    required this.bloc,
  });

  @override
  Widget build(BuildContext context) {
    if (state.paymentMethod == PaymentMethod.card) {
      // USD preset selector
      return FiatPresetSelector.usd(
        selectedPreset: _findFiatPreset(state.fiatAmount),
        customValue:
            _findFiatPreset(state.fiatAmount) == null ? state.fiatAmount : null,
        onPresetSelected: (amount) {
          bloc.add(UnifiedTopupAmountSelected(amount));
        },
        onCustomAmountChanged: (amount) {
          bloc.add(UnifiedTopupAmountSelected(amount));
        },
      );
    } else if (state.selectedToken != null) {
      // Token preset selector
      return FiatPresetSelector.token(
        token: state.selectedToken!,
        selectedPreset:
            _findTokenPreset(state.fiatAmount, state.selectedToken!),
        customValue:
            _findTokenPreset(state.fiatAmount, state.selectedToken!) == null
                ? state.fiatAmount
                : null,
        onPresetSelected: (amount) {
          bloc.add(UnifiedTopupAmountSelected(amount));
        },
        onCustomAmountChanged: (amount) {
          bloc.add(UnifiedTopupAmountSelected(amount));
        },
      );
    } else {
      // No token selected - show message
      return _SelectTokenMessage();
    }
  }

  double? _findFiatPreset(double amount) {
    for (final preset in defaultFiatPresets) {
      if (preset.toDouble() == amount) {
        return amount;
      }
    }
    return null;
  }

  double? _findTokenPreset(double amount, CryptoToken token) {
    final presets = tokenPresets[token] ?? [];
    for (final preset in presets) {
      if (preset == amount) {
        return amount;
      }
    }
    return null;
  }
}

class _SelectTokenMessage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.themeBgSubtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.themeBorderDefault),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: colors.themeFgMuted, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Select a cryptocurrency from the dropdown above to see amounts.',
              style: typography.paragraphSmall(color: colors.themeFgMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _PromoCodeSection extends StatefulWidget {
  final UnifiedTopupLoaded state;
  final UnifiedTopupBloc bloc;

  const _PromoCodeSection({
    required this.state,
    required this.bloc,
  });

  @override
  State<_PromoCodeSection> createState() => _PromoCodeSectionState();
}

class _PromoCodeSectionState extends State<_PromoCodeSection> {
  final TextEditingController _controller = TextEditingController();
  bool _isExpanded = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    // If promo code is applied, show it
    if (widget.state.promoCode != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.themeSuccessSubtle,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle,
                color: colors.themeSuccessDefault, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Promo code applied: ${widget.state.promoCode}',
                style: typography.paragraphSmall(
                  color: colors.themeSuccessDefault,
                  fontWeight: ArFontWeight.semiBold,
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.close,
                  color: colors.themeSuccessDefault, size: 18),
              onPressed: () {
                widget.bloc.add(const UnifiedTopupPromoCodeRemoved());
              },
            ),
          ],
        ),
      );
    }

    // Collapsible promo code input
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() {
              _isExpanded = !_isExpanded;
            });
          },
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  _isExpanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 18,
                  color: colors.themeFgMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  'Have a promo code?',
                  style: typography.paragraphSmall(
                    color: colors.themeFgMuted,
                    fontWeight: ArFontWeight.semiBold,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_isExpanded) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.themeBorderDefault),
                    borderRadius: BorderRadius.circular(8),
                    color: colors.themeBgCanvas,
                  ),
                  child: TextField(
                    controller: _controller,
                    style: typography.paragraphNormal(
                      color: colors.themeFgDefault,
                    ),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: InputBorder.none,
                      hintText: 'Enter promo code',
                      hintStyle: typography.paragraphNormal(
                        color: colors.themeFgDisabled,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 44,
                child: ArDriveButton(
                  style: ArDriveButtonStyle.secondary,
                  text: 'Apply',
                  maxHeight: 44,
                  fontStyle: ArDriveTypographyNew.of(context).paragraphSmall(
                    fontWeight: ArFontWeight.semiBold,
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeFgDefault,
                  ),
                  onPressed: () {
                    if (_controller.text.isNotEmpty) {
                      widget.bloc.add(
                        UnifiedTopupPromoCodeSubmitted(_controller.text.trim()),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _EmptySummaryPlaceholder extends StatelessWidget {
  const _EmptySummaryPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.themeBgSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.themeBorderDefault),
      ),
      child: Center(
        child: Text(
          'Select an amount to see purchase summary',
          style: typography.paragraphNormal(
            color: colors.themeFgMuted,
          ),
        ),
      ),
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  final String message;

  const _ErrorMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
              message,
              style: typography.paragraphSmall(
                color: colors.themeErrorDefault,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
