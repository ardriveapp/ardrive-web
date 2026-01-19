part of 'unified_topup_bloc.dart';

/// Base class for all unified topup states
sealed class UnifiedTopupState extends Equatable {
  const UnifiedTopupState();

  @override
  List<Object?> get props => [];
}

/// Initial state before data is loaded
class UnifiedTopupInitial extends UnifiedTopupState {
  const UnifiedTopupInitial();
}

/// Loading state while fetching initial data
class UnifiedTopupLoading extends UnifiedTopupState {
  const UnifiedTopupLoading();
}

/// Main loaded state with all selection data
class UnifiedTopupLoaded extends UnifiedTopupState {
  /// Selected payment method
  final PaymentMethod paymentMethod;

  /// Selected crypto token (when paymentMethod is crypto)
  final CryptoToken? selectedToken;

  /// Amount selection mode (storage or currency)
  final AmountMode amountMode;

  /// Selected amount in fiat (USD) for card, or token amount for crypto
  final double fiatAmount;

  /// Token amount for crypto payments (same as fiatAmount but named clearly)
  double get tokenAmount => fiatAmount;

  /// USD equivalent when paying with crypto tokens
  final double? usdEquivalent;

  /// Selected storage size (when amountMode is storage)
  final double? storageSize;

  /// Storage size unit
  final FileSizeUnit storageUnit;

  /// Display unit for storage estimates
  final FileSizeUnit displayUnit;

  /// Current user balance (in winc)
  final BigInt currentBalance;

  /// Estimated storage for current balance
  final String currentBalanceStorage;

  /// Credits to receive for selected amount
  final BigInt creditsToReceive;

  /// Estimated storage for selected amount
  final String estimatedStorage;

  /// Estimated storage for new balance (currentBalance + creditsToReceive)
  final String newBalanceStorage;

  /// Applied promo code (if any)
  final String? promoCode;

  /// Discount percentage from promo code
  final int? discountPercent;

  /// Whether price is currently being fetched
  final bool isLoadingQuote;

  /// Error message (if any)
  final String? errorMessage;

  const UnifiedTopupLoaded({
    required this.paymentMethod,
    this.selectedToken,
    required this.amountMode,
    required this.fiatAmount,
    this.usdEquivalent,
    this.storageSize,
    this.storageUnit = FileSizeUnit.gigabytes,
    this.displayUnit = FileSizeUnit.gigabytes,
    required this.currentBalance,
    required this.currentBalanceStorage,
    required this.creditsToReceive,
    required this.estimatedStorage,
    required this.newBalanceStorage,
    this.promoCode,
    this.discountPercent,
    this.isLoadingQuote = false,
    this.errorMessage,
  });

  /// New balance after purchase
  BigInt get newBalance => currentBalance + creditsToReceive;

  /// Whether an amount has been selected
  bool get hasAmount => fiatAmount > 0;

  /// Whether user can continue to confirmation
  bool get canContinue =>
      hasAmount &&
      !isLoadingQuote &&
      errorMessage == null &&
      (paymentMethod == PaymentMethod.card || selectedToken != null);

  /// Price symbol for display
  String get priceSymbol {
    if (paymentMethod == PaymentMethod.card) {
      return '\$';
    } else {
      return selectedToken?.symbol ?? '\$';
    }
  }

  /// Amount mode label for toggle
  String get amountModeLabel {
    if (paymentMethod == PaymentMethod.card) {
      return 'USD';
    } else {
      return selectedToken?.symbol ?? 'Token';
    }
  }

  UnifiedTopupLoaded copyWith({
    PaymentMethod? paymentMethod,
    CryptoToken? selectedToken,
    bool clearToken = false,
    AmountMode? amountMode,
    double? fiatAmount,
    double? usdEquivalent,
    bool clearUsdEquivalent = false,
    double? storageSize,
    bool clearStorageSize = false,
    FileSizeUnit? storageUnit,
    FileSizeUnit? displayUnit,
    BigInt? currentBalance,
    String? currentBalanceStorage,
    BigInt? creditsToReceive,
    String? estimatedStorage,
    String? newBalanceStorage,
    String? promoCode,
    bool clearPromoCode = false,
    int? discountPercent,
    bool clearDiscountPercent = false,
    bool? isLoadingQuote,
    String? errorMessage,
    bool clearError = false,
  }) {
    return UnifiedTopupLoaded(
      paymentMethod: paymentMethod ?? this.paymentMethod,
      selectedToken: clearToken ? null : (selectedToken ?? this.selectedToken),
      amountMode: amountMode ?? this.amountMode,
      fiatAmount: fiatAmount ?? this.fiatAmount,
      usdEquivalent:
          clearUsdEquivalent ? null : (usdEquivalent ?? this.usdEquivalent),
      storageSize:
          clearStorageSize ? null : (storageSize ?? this.storageSize),
      storageUnit: storageUnit ?? this.storageUnit,
      displayUnit: displayUnit ?? this.displayUnit,
      currentBalance: currentBalance ?? this.currentBalance,
      currentBalanceStorage:
          currentBalanceStorage ?? this.currentBalanceStorage,
      creditsToReceive: creditsToReceive ?? this.creditsToReceive,
      estimatedStorage: estimatedStorage ?? this.estimatedStorage,
      newBalanceStorage: newBalanceStorage ?? this.newBalanceStorage,
      promoCode: clearPromoCode ? null : (promoCode ?? this.promoCode),
      discountPercent: clearDiscountPercent
          ? null
          : (discountPercent ?? this.discountPercent),
      isLoadingQuote: isLoadingQuote ?? this.isLoadingQuote,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
        paymentMethod,
        selectedToken,
        amountMode,
        fiatAmount,
        usdEquivalent,
        storageSize,
        storageUnit,
        displayUnit,
        currentBalance,
        currentBalanceStorage,
        creditsToReceive,
        estimatedStorage,
        newBalanceStorage,
        promoCode,
        discountPercent,
        isLoadingQuote,
        errorMessage,
      ];
}

/// Error state when initialization fails
class UnifiedTopupError extends UnifiedTopupState {
  final String message;

  const UnifiedTopupError(this.message);

  @override
  List<Object?> get props => [message];
}

/// State when user is ready to continue to confirmation
class UnifiedTopupReadyToContinue extends UnifiedTopupState {
  final PaymentMethod paymentMethod;
  final CryptoToken? selectedToken;
  final double fiatAmount;
  final double? usdEquivalent;
  final BigInt creditsToReceive;
  final String? promoCode;

  const UnifiedTopupReadyToContinue({
    required this.paymentMethod,
    this.selectedToken,
    required this.fiatAmount,
    this.usdEquivalent,
    required this.creditsToReceive,
    this.promoCode,
  });

  /// For crypto payments, get the USD amount to pass to the crypto flow
  double get usdAmount => usdEquivalent ?? fiatAmount;

  @override
  List<Object?> get props => [
        paymentMethod,
        selectedToken,
        fiatAmount,
        usdEquivalent,
        creditsToReceive,
        promoCode,
      ];
}
