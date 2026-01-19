part of 'unified_topup_bloc.dart';

/// Base class for all unified topup events
sealed class UnifiedTopupEvent extends Equatable {
  const UnifiedTopupEvent();

  @override
  List<Object?> get props => [];
}

/// Initialize the unified topup flow
class UnifiedTopupStarted extends UnifiedTopupEvent {
  const UnifiedTopupStarted();
}

/// Payment method changed (card or crypto)
class UnifiedTopupPaymentMethodChanged extends UnifiedTopupEvent {
  final PaymentMethod method;
  final CryptoToken? token;

  const UnifiedTopupPaymentMethodChanged({
    required this.method,
    this.token,
  });

  @override
  List<Object?> get props => [method, token];
}

/// Amount selection mode changed (storage or currency)
class UnifiedTopupAmountModeChanged extends UnifiedTopupEvent {
  final AmountMode mode;

  const UnifiedTopupAmountModeChanged(this.mode);

  @override
  List<Object?> get props => [mode];
}

/// Fiat/currency amount selected
class UnifiedTopupAmountSelected extends UnifiedTopupEvent {
  final double amount;

  const UnifiedTopupAmountSelected(this.amount);

  @override
  List<Object?> get props => [amount];
}

/// Storage size selected
class UnifiedTopupStorageSizeSelected extends UnifiedTopupEvent {
  final double size;
  final FileSizeUnit unit;

  const UnifiedTopupStorageSizeSelected({
    required this.size,
    required this.unit,
  });

  @override
  List<Object?> get props => [size, unit];
}

/// Data unit changed for display
class UnifiedTopupDataUnitChanged extends UnifiedTopupEvent {
  final FileSizeUnit unit;

  const UnifiedTopupDataUnitChanged(this.unit);

  @override
  List<Object?> get props => [unit];
}

/// Promo code submitted
class UnifiedTopupPromoCodeSubmitted extends UnifiedTopupEvent {
  final String code;

  const UnifiedTopupPromoCodeSubmitted(this.code);

  @override
  List<Object?> get props => [code];
}

/// Promo code removed
class UnifiedTopupPromoCodeRemoved extends UnifiedTopupEvent {
  const UnifiedTopupPromoCodeRemoved();
}

/// Continue button pressed - proceed to confirmation
class UnifiedTopupContinuePressed extends UnifiedTopupEvent {
  const UnifiedTopupContinuePressed();
}

/// Go back from continue/confirmation state to loaded state
class UnifiedTopupBackToLoaded extends UnifiedTopupEvent {
  const UnifiedTopupBackToLoaded();
}

/// Price estimate updated
class UnifiedTopupPriceEstimateUpdated extends UnifiedTopupEvent {
  final PriceEstimate estimate;

  const UnifiedTopupPriceEstimateUpdated(this.estimate);

  @override
  List<Object?> get props => [estimate];
}
