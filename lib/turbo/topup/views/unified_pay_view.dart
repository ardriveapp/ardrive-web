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
          child: ArDriveSpinner(size: ArDriveSpinnerSize.large),
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

    return TurboTopupScaffold(
      title: 'Buy Turbo Credits',
      actions: [
        ModalAction(
          title: state.isLoadingQuote ? 'Loading...' : 'Continue',
          isEnable: state.canContinue && !state.isLoadingQuote,
          action: () => bloc.add(const UnifiedTopupContinuePressed()),
        ),
      ],
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

          // Error message
          if (state.errorMessage != null) ...[
            const SizedBox(height: 16),
            _ErrorMessage(message: state.errorMessage!),
          ],
        ],
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
    return const ArDriveNotice(
      type: ArDriveNoticeType.info,
      message:
          'Select a cryptocurrency from the dropdown above to see amounts.',
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
    final typography = ArDriveTypographyNew.of(context);

    // If promo code is applied, show it
    if (widget.state.promoCode != null) {
      return ArDriveNotice(
        type: ArDriveNoticeType.success,
        message: 'Promo code applied: ${widget.state.promoCode}',
        dismissLabel: 'Remove promo code',
        onDismiss: () => widget.bloc.add(const UnifiedTopupPromoCodeRemoved()),
      );
    }

    void submit() {
      if (_controller.text.trim().isNotEmpty) {
        widget.bloc
            .add(UnifiedTopupPromoCodeSubmitted(_controller.text.trim()));
      }
    }

    // A link that opens the promo code field: announced as a button, and
    // reachable with the keyboard.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ArDriveLink(
          text: 'Have a promo code?',
          isAction: true,
          style: typography.paragraphSmall(fontWeight: ArFontWeight.semiBold),
          onTap: () => setState(() => _isExpanded = !_isExpanded),
        ),
        if (_isExpanded) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: ArDriveTextFieldNew(
                  controller: _controller,
                  hintText: 'Enter promo code',
                  onFieldSubmitted: (_) => submit(),
                ),
              ),
              const SizedBox(width: 8),
              ArDriveButtonNew(
                typography: ArDriveTypographyNew.of(context),
                variant: ButtonVariant.secondary,
                text: 'Apply',
                onPressed: submit,
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
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.containerRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.strokeMid),
      ),
      child: Center(
        child: Text(
          'Select an amount to see purchase summary',
          style: typography.paragraphNormal(
            color: colors.textMid,
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
    return ArDriveNotice(type: ArDriveNoticeType.error, message: message);
  }
}
