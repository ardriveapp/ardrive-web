// Stub implementation for non-web platforms

import 'package:ardrive/turbo/config/crypto_network_config.dart';
import 'package:ardrive/turbo/services/crypto_price_service.dart';
import 'package:ardrive/turbo/services/ethereum_wallet_service.dart';
import 'package:ardrive/turbo/services/solana_wallet_service.dart';
import 'package:ardrive/turbo/services/wallet_signer_cache.dart';
import 'package:ardrive/turbo/topup/models/crypto_payment_result.dart';
import 'package:ardrive/turbo/topup/models/crypto_quote.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/models/pending_transaction.dart';
import 'package:ardrive/turbo/topup/models/wallet_connection_state.dart';
import 'package:ardrive_http/ardrive_http.dart';

/// Service for cryptocurrency payment operations.
///
/// Stub implementation for non-web platforms.
class CryptoPaymentService {
  CryptoPaymentService({
    required CryptoNetworkConfig networkConfig,
    required ArDriveHTTP httpClient,
    required WalletSignerCache signerCache,
    CryptoPriceService? priceService,
  });

  /// Get a quote for a cryptocurrency top-up.
  Future<CryptoQuote> getQuote({
    required CryptoToken token,
    required double usdAmount,
    String? promoCode,
    String? destinationAddress,
  }) async {
    throw UnsupportedError(
        'Crypto payments are only available on web platforms');
  }

  /// Get quote by token amount (instead of USD amount)
  Future<CryptoQuote> getQuoteByTokenAmount({
    required CryptoToken token,
    required double tokenAmount,
    String? promoCode,
    String? destinationAddress,
  }) async {
    throw UnsupportedError(
        'Crypto payments are only available on web platforms');
  }

  /// Validate a promo code
  Future<PromoCodeValidation> validatePromoCode({
    required String code,
    required double usdAmount,
    String? destinationAddress,
  }) async {
    throw UnsupportedError(
        'Crypto payments are only available on web platforms');
  }

  /// Execute a cryptocurrency payment.
  Future<CryptoPaymentResult> executePayment({
    required CryptoToken token,
    required CryptoQuote quote,
    required String arweaveAddress,
    EthereumWalletService? ethereumWallet,
    SolanaWalletService? solanaWallet,
  }) async {
    throw UnsupportedError(
        'Crypto payments are only available on web platforms');
  }

  /// Submit a pending transaction for retry/recovery.
  Future<CryptoPaymentResult> submitPendingTransaction(
    PendingCryptoTransaction pendingTx, {
    EthereumWalletService? ethereumWallet,
    SolanaWalletService? solanaWallet,
  }) async {
    throw UnsupportedError(
        'Crypto payments are only available on web platforms');
  }

  /// Get token balance for a connected wallet.
  Future<TokenBalance> getTokenBalance({
    required CryptoToken token,
    EthereumWalletService? ethereumWallet,
    SolanaWalletService? solanaWallet,
    String? arweaveAddress,
  }) async {
    return TokenBalance.error(
        token, 'Crypto payments are only available on web platforms');
  }

  /// Estimate network fee for a payment.
  Future<double> estimateNetworkFee({
    required CryptoToken token,
    EthereumWalletService? ethereumWallet,
  }) async {
    return 0;
  }

  /// Get the current USD price per token
  Future<double> getTokenPrice(CryptoToken token) async {
    throw UnsupportedError(
        'Crypto payments are only available on web platforms');
  }

  /// Convert token amount to USD value
  Future<double> tokenToUsd(CryptoToken token, double tokenAmount) async {
    throw UnsupportedError(
        'Crypto payments are only available on web platforms');
  }

  /// Convert USD amount to token amount
  Future<double> usdToToken(CryptoToken token, double usdAmount) async {
    throw UnsupportedError(
        'Crypto payments are only available on web platforms');
  }

  /// Refresh price cache
  Future<void> refreshPrices() async {}
}

/// Result of promo code validation
class PromoCodeValidation {
  final bool isValid;
  final String? errorMessage;
  final double? discountPercent;
  final String? adjustmentName;

  PromoCodeValidation({
    required this.isValid,
    this.errorMessage,
    this.discountPercent,
    this.adjustmentName,
  });
}

/// Exception for crypto payment operations
class CryptoPaymentException implements Exception {
  final String message;
  final String? promoCode;

  CryptoPaymentException(this.message, {this.promoCode});

  factory CryptoPaymentException.invalidPromoCode(String code) {
    return CryptoPaymentException(
      'Invalid promo code',
      promoCode: code,
    );
  }

  bool get isInvalidPromoCode => promoCode != null;

  @override
  String toString() => 'CryptoPaymentException: $message';
}
