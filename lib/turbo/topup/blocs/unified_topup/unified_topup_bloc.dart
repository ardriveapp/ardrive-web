import 'dart:async';

import 'package:ardrive/turbo/services/crypto_price_service.dart';
import 'package:ardrive/turbo/topup/components/amount_mode_toggle.dart';
import 'package:ardrive/turbo/topup/components/fiat_preset_selector.dart';
import 'package:ardrive/turbo/topup/components/payment_method_selector.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/models/price_estimate.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/turbo/utils/utils.dart';
import 'package:ardrive/utils/file_size_units.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'unified_topup_event.dart';
part 'unified_topup_state.dart';

/// Default fiat amount when nothing is selected
const double defaultFiatAmount = 0;

/// BLoC managing the unified topup pay page.
///
/// This bloc orchestrates:
/// - Payment method selection (card/crypto)
/// - Amount mode selection (storage/currency)
/// - Amount selection (presets or custom)
/// - Price estimates
/// - Balance calculations
class UnifiedTopupBloc extends Bloc<UnifiedTopupEvent, UnifiedTopupState> {
  final Turbo turbo;
  final CryptoPriceService priceService;

  StreamSubscription<PriceEstimate>? _priceEstimateSubscription;

  /// Stores the last loaded state for restoring when going back
  UnifiedTopupLoaded? _lastLoadedState;

  UnifiedTopupBloc({
    required this.turbo,
    required this.priceService,
  }) : super(const UnifiedTopupInitial()) {
    // Listen to price estimate changes from Turbo service
    _priceEstimateSubscription =
        turbo.onPriceEstimateChanged.listen((estimate) {
      add(UnifiedTopupPriceEstimateUpdated(estimate));
    });

    on<UnifiedTopupStarted>(_onStarted);
    on<UnifiedTopupPaymentMethodChanged>(_onPaymentMethodChanged);
    on<UnifiedTopupAmountModeChanged>(_onAmountModeChanged);
    on<UnifiedTopupAmountSelected>(_onAmountSelected);
    on<UnifiedTopupStorageSizeSelected>(_onStorageSizeSelected);
    on<UnifiedTopupDataUnitChanged>(_onDataUnitChanged);
    on<UnifiedTopupPromoCodeSubmitted>(_onPromoCodeSubmitted);
    on<UnifiedTopupPromoCodeRemoved>(_onPromoCodeRemoved);
    on<UnifiedTopupContinuePressed>(_onContinuePressed);
    on<UnifiedTopupBackToLoaded>(_onBackToLoaded);
    on<UnifiedTopupPriceEstimateUpdated>(_onPriceEstimateUpdated);
  }

  @override
  Future<void> close() {
    _priceEstimateSubscription?.cancel();
    return super.close();
  }

  Future<void> _onStarted(
    UnifiedTopupStarted event,
    Emitter<UnifiedTopupState> emit,
  ) async {
    emit(const UnifiedTopupLoading());

    try {
      // Get initial balance
      final balance = await turbo.getBalance();

      // Get storage estimate for balance
      final balanceStorage = await turbo.computeStorageEstimateForCredits(
        credits: balance,
        outputDataUnit: FileSizeUnit.gigabytes,
      );

      emit(UnifiedTopupLoaded(
        paymentMethod: PaymentMethod.card,
        amountMode: AmountMode.currency,
        fiatAmount: defaultFiatAmount,
        currentBalance: balance,
        currentBalanceStorage:
            formatStorageWithDynamicUnit(balanceStorage, includeApprox: false),
        creditsToReceive: BigInt.zero,
        estimatedStorage: '0',
        newBalanceStorage:
            formatStorageWithDynamicUnit(balanceStorage, includeApprox: false),
      ));
    } catch (e, s) {
      logger.e('Error initializing unified topup', e, s);
      emit(UnifiedTopupError(e.toString()));
    }
  }

  Future<void> _onPaymentMethodChanged(
    UnifiedTopupPaymentMethodChanged event,
    Emitter<UnifiedTopupState> emit,
  ) async {
    final currentState = state;
    if (currentState is! UnifiedTopupLoaded) return;

    // Reset amount when switching payment methods
    emit(currentState.copyWith(
      paymentMethod: event.method,
      selectedToken: event.token,
      clearToken: event.method == PaymentMethod.card,
      // Reset to currency mode when switching
      amountMode: AmountMode.currency,
      fiatAmount: 0,
      clearStorageSize: true,
      creditsToReceive: BigInt.zero,
      estimatedStorage: '0',
      newBalanceStorage:
          currentState.currentBalanceStorage, // Reset to current balance
      clearError: true,
    ));
  }

  Future<void> _onAmountModeChanged(
    UnifiedTopupAmountModeChanged event,
    Emitter<UnifiedTopupState> emit,
  ) async {
    final currentState = state;
    if (currentState is! UnifiedTopupLoaded) return;

    // Reset amount when switching modes
    emit(currentState.copyWith(
      amountMode: event.mode,
      fiatAmount: 0,
      clearStorageSize: true,
      creditsToReceive: BigInt.zero,
      estimatedStorage: '0',
      newBalanceStorage:
          currentState.currentBalanceStorage, // Reset to current balance
      clearError: true,
    ));
  }

  Future<void> _onAmountSelected(
    UnifiedTopupAmountSelected event,
    Emitter<UnifiedTopupState> emit,
  ) async {
    final currentState = state;
    if (currentState is! UnifiedTopupLoaded) return;

    if (event.amount <= 0) {
      emit(currentState.copyWith(
        fiatAmount: 0,
        creditsToReceive: BigInt.zero,
        estimatedStorage: '0',
        newBalanceStorage: currentState.currentBalanceStorage,
        clearUsdEquivalent: true,
      ));
      return;
    }

    emit(currentState.copyWith(
      fiatAmount: event.amount,
      isLoadingQuote: true,
      clearError: true,
    ));

    try {
      // For crypto payments, convert token amount to USD first
      double usdAmount;
      double? usdEquivalent;

      if (currentState.paymentMethod == PaymentMethod.crypto &&
          currentState.selectedToken != null) {
        // Convert token amount to USD using live CoinGecko prices
        usdEquivalent =
            await _getUsdValue(currentState.selectedToken!, event.amount);
        usdAmount = usdEquivalent;
      } else {
        // Card payment - amount is already in USD
        usdAmount = event.amount;
      }

      // Compute price estimate using USD amount
      final estimate = await turbo.computePriceEstimate(
        currentAmount: usdAmount,
        currentCurrency: 'usd',
        currentDataUnit: currentState.displayUnit,
        promoCode: turbo.promoCode,
      );

      // Check if state is still valid
      if (state is UnifiedTopupLoaded) {
        final loadedState = state as UnifiedTopupLoaded;
        final newBalanceStorage = await _calculateNewBalanceStorage(
          loadedState.currentBalance,
          estimate.estimate.winstonCredits,
          loadedState.displayUnit,
        );
        emit(loadedState.copyWith(
          fiatAmount: event.amount,
          usdEquivalent: usdEquivalent,
          creditsToReceive: estimate.estimate.winstonCredits,
          estimatedStorage: formatStorageWithDynamicUnit(
              estimate.estimatedStorage,
              includeApprox: false),
          newBalanceStorage: newBalanceStorage,
          isLoadingQuote: false,
        ));
      }
    } catch (e, s) {
      logger.e('Error computing price estimate', e, s);
      if (state is UnifiedTopupLoaded) {
        emit((state as UnifiedTopupLoaded).copyWith(
          isLoadingQuote: false,
          errorMessage: 'Failed to get price estimate',
        ));
      }
    }
  }

  /// Gets the USD value of a given token amount using live CoinGecko prices.
  Future<double> _getUsdValue(CryptoToken token, double tokenAmount) async {
    return priceService.tokenToUsd(token, tokenAmount);
  }

  Future<void> _onStorageSizeSelected(
    UnifiedTopupStorageSizeSelected event,
    Emitter<UnifiedTopupState> emit,
  ) async {
    final currentState = state;
    if (currentState is! UnifiedTopupLoaded) return;

    if (event.size <= 0) {
      emit(currentState.copyWith(
        storageSize: 0,
        storageUnit: event.unit,
        fiatAmount: 0,
        creditsToReceive: BigInt.zero,
        estimatedStorage: '0',
        newBalanceStorage: currentState.currentBalanceStorage,
      ));
      return;
    }

    emit(currentState.copyWith(
      storageSize: event.size,
      storageUnit: event.unit,
      isLoadingQuote: true,
      clearError: true,
    ));

    try {
      // Convert storage size to GB for pricing
      final sizeInGB = _storageSizeToGB(event.size, event.unit);

      // Get the cost of 1 GB in winc
      final costOfOneGbInWinc = await turbo.getCostOfOneGB();

      // Calculate the cost in winc for the desired storage
      final storageCostInWinc = BigInt.from(
        (costOfOneGbInWinc.toDouble() * sizeInGB).round(),
      );

      // Get the exchange rate by checking what $10 USD buys in winc
      // Using $10 as base since minimum amount is $5
      const baseUsdAmount = 10.0;
      final baseEstimate = await turbo.computePriceEstimate(
        currentAmount: baseUsdAmount,
        currentCurrency: 'usd',
        currentDataUnit: event.unit,
        promoCode: null,
      );

      // Calculate USD amount: (storageCost / winc_per_dollar)
      final wincPerDollar =
          baseEstimate.estimate.winstonCredits.toDouble() / baseUsdAmount;

      if (wincPerDollar <= 0) {
        throw Exception('Could not determine exchange rate');
      }

      final priceInUsd = storageCostInWinc.toDouble() / wincPerDollar;

      if (priceInUsd <= 0) {
        throw Exception('Could not determine price for storage');
      }

      // Check minimum amount for card payments
      if (currentState.paymentMethod == PaymentMethod.card &&
          priceInUsd < minFiatAmount) {
        if (state is UnifiedTopupLoaded) {
          emit((state as UnifiedTopupLoaded).copyWith(
            storageSize: event.size,
            storageUnit: event.unit,
            fiatAmount: priceInUsd,
            creditsToReceive: BigInt.zero,
            estimatedStorage: event.size.toStringAsFixed(
              event.size == event.size.roundToDouble() ? 0 : 2,
            ),
            isLoadingQuote: false,
            errorMessage:
                'Minimum purchase is \$$minFiatAmount for card payments. Please select a larger storage amount.',
          ));
        }
        return;
      }

      // Now compute the full price estimate with correct amount
      final estimate = await turbo.computePriceEstimate(
        currentAmount: priceInUsd,
        currentCurrency: 'usd',
        currentDataUnit: event.unit,
        promoCode: currentState.promoCode,
      );

      if (state is UnifiedTopupLoaded) {
        final loadedState = state as UnifiedTopupLoaded;
        final newBalanceStorage = await _calculateNewBalanceStorage(
          loadedState.currentBalance,
          estimate.estimate.winstonCredits,
          loadedState.displayUnit,
        );
        emit(loadedState.copyWith(
          storageSize: event.size,
          storageUnit: event.unit,
          fiatAmount: priceInUsd,
          creditsToReceive: estimate.estimate.winstonCredits,
          estimatedStorage: formatStorageWithDynamicUnit(
              estimate.estimatedStorage,
              includeApprox: false),
          newBalanceStorage: newBalanceStorage,
          isLoadingQuote: false,
          clearError: true,
        ));
      }
    } catch (e, s) {
      logger.e('Error computing storage price', e, s);
      if (state is UnifiedTopupLoaded) {
        emit((state as UnifiedTopupLoaded).copyWith(
          isLoadingQuote: false,
          errorMessage:
              'Failed to get storage price. Please try a different amount.',
        ));
      }
    }
  }

  /// Calculates the storage estimate for the new balance (current + credits to receive)
  Future<String> _calculateNewBalanceStorage(
    BigInt currentBalance,
    BigInt creditsToReceive,
    FileSizeUnit displayUnit,
  ) async {
    final newBalance = currentBalance + creditsToReceive;
    final storage = await turbo.computeStorageEstimateForCredits(
      credits: newBalance,
      outputDataUnit:
          FileSizeUnit.gigabytes, // Always get in GiB for dynamic formatting
    );
    return formatStorageWithDynamicUnit(storage, includeApprox: false);
  }

  /// Converts storage size to GB equivalent
  double _storageSizeToGB(double size, FileSizeUnit unit) {
    switch (unit) {
      case FileSizeUnit.bytes:
        return size / (1024 * 1024 * 1024);
      case FileSizeUnit.kilobytes:
        return size / (1024 * 1024);
      case FileSizeUnit.megabytes:
        return size / 1024;
      case FileSizeUnit.gigabytes:
        return size;
    }
  }

  Future<void> _onDataUnitChanged(
    UnifiedTopupDataUnitChanged event,
    Emitter<UnifiedTopupState> emit,
  ) async {
    final currentState = state;
    if (currentState is! UnifiedTopupLoaded) return;

    // Update display unit
    emit(currentState.copyWith(displayUnit: event.unit));

    // Recalculate storage estimates with new unit
    // For crypto payments, use usdEquivalent; for card payments, use fiatAmount
    final isCrypto = currentState.paymentMethod == PaymentMethod.crypto;
    final amountForEstimate =
        isCrypto ? currentState.usdEquivalent : currentState.fiatAmount;

    if (amountForEstimate != null && amountForEstimate > 0) {
      try {
        final balanceStorage = await turbo.computeStorageEstimateForCredits(
          credits: currentState.currentBalance,
          outputDataUnit: event.unit,
        );

        final estimate = await turbo.computePriceEstimate(
          currentAmount: amountForEstimate,
          currentCurrency: 'usd',
          currentDataUnit: event.unit,
          promoCode: turbo.promoCode,
        );

        if (state is UnifiedTopupLoaded) {
          final loadedState = state as UnifiedTopupLoaded;
          final newBalanceStorage = await _calculateNewBalanceStorage(
            loadedState.currentBalance,
            estimate.estimate.winstonCredits,
            event.unit,
          );
          emit(loadedState.copyWith(
            displayUnit: event.unit,
            currentBalanceStorage: formatStorageWithDynamicUnit(balanceStorage,
                includeApprox: false),
            estimatedStorage: formatStorageWithDynamicUnit(
                estimate.estimatedStorage,
                includeApprox: false),
            newBalanceStorage: newBalanceStorage,
          ));
        }
      } catch (e) {
        logger.e('Error updating display unit', e);
      }
    }
  }

  Future<void> _onPromoCodeSubmitted(
    UnifiedTopupPromoCodeSubmitted event,
    Emitter<UnifiedTopupState> emit,
  ) async {
    final currentState = state;
    if (currentState is! UnifiedTopupLoaded) return;

    emit(currentState.copyWith(
      promoCode: event.code,
      isLoadingQuote: true,
    ));

    // Refresh estimate with promo code
    // For crypto payments, use usdEquivalent; for card payments, use fiatAmount
    final isCrypto = currentState.paymentMethod == PaymentMethod.crypto;
    final amountForEstimate =
        isCrypto ? currentState.usdEquivalent : currentState.fiatAmount;

    if (amountForEstimate != null && amountForEstimate > 0) {
      try {
        final estimate = await turbo.computePriceEstimate(
          currentAmount: amountForEstimate,
          currentCurrency: 'usd',
          currentDataUnit: currentState.displayUnit,
          promoCode: event.code,
        );

        if (state is UnifiedTopupLoaded) {
          final loadedState = state as UnifiedTopupLoaded;
          // Check if promo code provided a multiplicative discount
          // Only 'multiply' adjustments represent percentage discounts
          // (e.g., operatorMagnitude of 0.9 = 10% discount)
          final multiplicativeAdjustment = estimate.estimate.adjustments
              .where((adj) => adj.operator == 'multiply')
              .firstOrNull;
          final hasDiscount = multiplicativeAdjustment != null;
          int? discountPercent;
          if (hasDiscount) {
            // Use the adjustment's discountPercentage getter
            discountPercent =
                multiplicativeAdjustment.discountPercentage.round();
            // Ensure we don't show negative or invalid percentages
            if (discountPercent <= 0) {
              discountPercent = null;
            }
          }

          final newBalanceStorage = await _calculateNewBalanceStorage(
            loadedState.currentBalance,
            estimate.estimate.winstonCredits,
            loadedState.displayUnit,
          );
          emit(loadedState.copyWith(
            promoCode: event.code,
            discountPercent: discountPercent,
            creditsToReceive: estimate.estimate.winstonCredits,
            estimatedStorage: formatStorageWithDynamicUnit(
                estimate.estimatedStorage,
                includeApprox: false),
            newBalanceStorage: newBalanceStorage,
            isLoadingQuote: false,
          ));
        }
      } catch (e) {
        logger.e('Error applying promo code', e);
        if (state is UnifiedTopupLoaded) {
          emit((state as UnifiedTopupLoaded).copyWith(
            clearPromoCode: true,
            clearDiscountPercent: true,
            isLoadingQuote: false,
            errorMessage: 'Invalid promo code',
          ));
        }
      }
    } else {
      emit(currentState.copyWith(
        promoCode: event.code,
        isLoadingQuote: false,
      ));
    }
  }

  Future<void> _onPromoCodeRemoved(
    UnifiedTopupPromoCodeRemoved event,
    Emitter<UnifiedTopupState> emit,
  ) async {
    final currentState = state;
    if (currentState is! UnifiedTopupLoaded) return;

    emit(currentState.copyWith(
      clearPromoCode: true,
      clearDiscountPercent: true,
    ));

    // Refresh estimate without promo code
    // For crypto payments, use usdEquivalent; for card payments, use fiatAmount
    final isCrypto = currentState.paymentMethod == PaymentMethod.crypto;
    final amountForEstimate =
        isCrypto ? (currentState.usdEquivalent ?? 0) : currentState.fiatAmount;

    if (amountForEstimate > 0) {
      try {
        final estimate = await turbo.computePriceEstimate(
          currentAmount: amountForEstimate,
          currentCurrency: 'usd',
          currentDataUnit: currentState.displayUnit,
          promoCode: null,
        );

        if (state is UnifiedTopupLoaded) {
          final loadedState = state as UnifiedTopupLoaded;
          final newBalanceStorage = await _calculateNewBalanceStorage(
            loadedState.currentBalance,
            estimate.estimate.winstonCredits,
            loadedState.displayUnit,
          );
          emit(loadedState.copyWith(
            creditsToReceive: estimate.estimate.winstonCredits,
            estimatedStorage: formatStorageWithDynamicUnit(
                estimate.estimatedStorage,
                includeApprox: false),
            newBalanceStorage: newBalanceStorage,
          ));
        }
      } catch (e) {
        logger.e('Error refreshing estimate', e);
      }
    }
  }

  Future<void> _onContinuePressed(
    UnifiedTopupContinuePressed event,
    Emitter<UnifiedTopupState> emit,
  ) async {
    final currentState = state;
    if (currentState is! UnifiedTopupLoaded) return;

    if (!currentState.canContinue) return;

    // Save the loaded state for later restoration when going back
    _lastLoadedState = currentState;

    // Emit ready to continue state
    emit(UnifiedTopupReadyToContinue(
      paymentMethod: currentState.paymentMethod,
      selectedToken: currentState.selectedToken,
      fiatAmount: currentState.fiatAmount,
      usdEquivalent: currentState.usdEquivalent,
      creditsToReceive: currentState.creditsToReceive,
      promoCode: currentState.promoCode,
      currentBalance: currentState.currentBalance,
      currentBalanceStorage: currentState.currentBalanceStorage,
      newBalanceStorage: currentState.newBalanceStorage,
    ));
  }

  void _onBackToLoaded(
    UnifiedTopupBackToLoaded event,
    Emitter<UnifiedTopupState> emit,
  ) {
    // Restore the last loaded state if available
    if (_lastLoadedState != null) {
      emit(_lastLoadedState!);
    }
  }

  Future<void> _onPriceEstimateUpdated(
    UnifiedTopupPriceEstimateUpdated event,
    Emitter<UnifiedTopupState> emit,
  ) async {
    final currentState = state;
    if (currentState is! UnifiedTopupLoaded) return;

    // Calculate new balance storage
    final newBalanceStorage = await _calculateNewBalanceStorage(
      currentState.currentBalance,
      event.estimate.estimate.winstonCredits,
      currentState.displayUnit,
    );

    // Update with new price estimate
    emit(currentState.copyWith(
      creditsToReceive: event.estimate.estimate.winstonCredits,
      estimatedStorage: formatStorageWithDynamicUnit(
          event.estimate.estimatedStorage,
          includeApprox: false),
      newBalanceStorage: newBalanceStorage,
    ));
  }
}
