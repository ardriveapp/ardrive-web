import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/models/payment_model.dart';
import 'package:ardrive/turbo/utils/utils.dart';
import 'package:equatable/equatable.dart';

/// Quote for a cryptocurrency top-up payment.
///
/// Contains the conversion rate between token amount and Turbo credits,
/// along with storage estimates and expiration time.
class CryptoQuote extends Equatable {
  /// The token type for this quote
  final CryptoToken token;

  /// Amount of tokens to pay (in smallest unit, e.g., wei, lamports, mARIO)
  final BigInt tokenAmount;

  /// Amount of winc (winston credits) to receive
  final BigInt wincAmount;

  /// Human-readable credits amount for display
  final double creditsDisplay;

  /// Estimated storage in GiB for this amount
  final double estimatedStorageGiB;

  /// USD value of the payment
  final double usdValue;

  /// Estimated network fee in USD (for gas, etc.)
  final double? networkFeeUsd;

  /// Applied promo code adjustment (if any)
  final Adjustment? adjustment;

  /// When this quote expires (typically 5 minutes from creation)
  final DateTime expiresAt;

  /// Original credits amount before any discount
  final double? originalCreditsDisplay;

  const CryptoQuote({
    required this.token,
    required this.tokenAmount,
    required this.wincAmount,
    required this.creditsDisplay,
    required this.estimatedStorageGiB,
    required this.usdValue,
    this.networkFeeUsd,
    this.adjustment,
    required this.expiresAt,
    this.originalCreditsDisplay,
  });

  /// Whether the quote has expired
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Time remaining until expiration
  Duration get timeRemaining {
    final remaining = expiresAt.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Whether a promo code discount is applied
  bool get hasDiscount => adjustment != null;

  /// The discount percentage (0-100)
  double get discountPercentage => adjustment?.discountPercentage ?? 0;

  /// Human-readable token amount for display
  double get tokenAmountDisplay =>
      tokenAmount.toDouble() / _getDecimalDivisor(token);

  /// Format the token amount with symbol for display
  String get formattedTokenAmount =>
      '${tokenAmountDisplay.toStringAsFixed(_getDisplayDecimals(token))} ${token.symbol}';

  /// Format the USD value for display
  String get formattedUsdValue => '\$${usdValue.toStringAsFixed(2)}';

  /// Format the credits for display
  String get formattedCredits => '${creditsDisplay.toStringAsFixed(3)} Credits';

  /// Format the storage estimate for display with dynamic units
  String get formattedStorage =>
      formatStorageWithDynamicUnit(estimatedStorageGiB);

  /// Format network fee for display
  String get formattedNetworkFee {
    if (networkFeeUsd == null || networkFeeUsd == 0) {
      return 'No fee';
    }
    return '~\$${networkFeeUsd!.toStringAsFixed(2)} (estimated)';
  }

  static double _getDecimalDivisor(CryptoToken token) {
    return switch (token.decimals) {
      6 => 1e6,
      9 => 1e9,
      18 => 1e18,
      _ => 1e6,
    };
  }

  static int _getDisplayDecimals(CryptoToken token) {
    return switch (token) {
      CryptoToken.ethBase || CryptoToken.ethL1 => 6,
      CryptoToken.sol => 4,
      _ => 2,
    };
  }

  /// Create a copy with updated values
  CryptoQuote copyWith({
    CryptoToken? token,
    BigInt? tokenAmount,
    BigInt? wincAmount,
    double? creditsDisplay,
    double? estimatedStorageGiB,
    double? usdValue,
    double? networkFeeUsd,
    Adjustment? adjustment,
    DateTime? expiresAt,
    double? originalCreditsDisplay,
  }) {
    return CryptoQuote(
      token: token ?? this.token,
      tokenAmount: tokenAmount ?? this.tokenAmount,
      wincAmount: wincAmount ?? this.wincAmount,
      creditsDisplay: creditsDisplay ?? this.creditsDisplay,
      estimatedStorageGiB: estimatedStorageGiB ?? this.estimatedStorageGiB,
      usdValue: usdValue ?? this.usdValue,
      networkFeeUsd: networkFeeUsd ?? this.networkFeeUsd,
      adjustment: adjustment ?? this.adjustment,
      expiresAt: expiresAt ?? this.expiresAt,
      originalCreditsDisplay:
          originalCreditsDisplay ?? this.originalCreditsDisplay,
    );
  }

  @override
  List<Object?> get props => [
        token,
        tokenAmount,
        wincAmount,
        creditsDisplay,
        estimatedStorageGiB,
        usdValue,
        networkFeeUsd,
        adjustment,
        expiresAt,
        originalCreditsDisplay,
      ];

  @override
  String toString() {
    return 'CryptoQuote{token: $token, tokenAmount: $tokenAmount, '
        'wincAmount: $wincAmount, creditsDisplay: $creditsDisplay, '
        'usdValue: $usdValue, expiresAt: $expiresAt}';
  }
}

/// Result of comparing two quotes for price volatility
class QuoteComparison extends Equatable {
  final CryptoQuote originalQuote;
  final CryptoQuote newQuote;

  const QuoteComparison({
    required this.originalQuote,
    required this.newQuote,
  });

  /// The percentage change in credits received
  /// Positive = more credits (good for user)
  /// Negative = fewer credits (bad for user)
  double get percentChange {
    if (originalQuote.creditsDisplay == 0) return 0;
    return ((newQuote.creditsDisplay - originalQuote.creditsDisplay) /
            originalQuote.creditsDisplay) *
        100;
  }

  /// Whether the price change exceeds the volatility threshold (5%)
  bool get exceedsVolatilityThreshold => percentChange.abs() > 5;

  /// Whether the new price is worse for the user (fewer credits)
  bool get isPriceWorse => percentChange < 0;

  @override
  List<Object> get props => [originalQuote, newQuote];
}
