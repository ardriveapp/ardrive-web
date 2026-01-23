// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:js_util';

import 'package:ardrive/turbo/config/crypto_network_config.dart';
import 'package:ardrive/turbo/services/turbo_sdk_interop.dart';
import 'package:ardrive/turbo/topup/models/crypto_quote.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/models/payment_model.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:js/js.dart';

/// High-level service for interacting with the Turbo SDK.
///
/// Provides type-safe Dart methods for:
/// - Getting quotes for crypto payments
/// - Executing token top-ups
/// - Managing balances
class TurboSDKService {
  final CryptoNetworkConfig _networkConfig;

  /// Cached unauthenticated clients per token type
  final Map<String, Object> _unauthenticatedClients = {};

  TurboSDKService({required CryptoNetworkConfig networkConfig})
      : _networkConfig = networkConfig;

  /// Check if the Turbo SDK is available
  bool get isSDKAvailable => isTurboSDKLoaded;

  /// Get SDK loading error if any
  String? get sdkError => turboSDKError;

  /// Ensure SDK is loaded and throw user-friendly error if not
  void ensureSDKAvailable() {
    if (!isSDKAvailable) {
      throw TurboSDKNotLoadedException(
        sdkError ?? 'Cryptocurrency payments are temporarily unavailable.',
      );
    }
  }

  // ============================================
  // Quote / Pricing
  // ============================================

  /// Get a quote for converting token amount to credits.
  ///
  /// Returns the amount of winc (winston credits) for the given token amount.
  Future<CryptoQuote> getQuote({
    required CryptoToken token,
    required double tokenAmount,
    Adjustment? adjustment,
  }) async {
    ensureSDKAvailable();

    try {
      final client = await _getUnauthenticatedClient(token);

      // Convert token amount to smallest unit
      final tokenAmountObj = _convertTokenAmount(token, tokenAmount);

      // Get winc for token
      final wincAmount = await getWincForToken(client, tokenAmountObj);

      // Calculate credit display value (winc / 1e12)
      final creditsDisplay = wincAmount.toDouble() / 1e12;

      // Estimate storage (assuming ~1GB per $5 worth of credits)
      // This is a rough estimate; actual may vary
      final usdValue = _estimateUsdValue(token, tokenAmount);
      final estimatedStorageGiB = creditsDisplay / 0.2; // Roughly $0.2 per GB

      return CryptoQuote(
        token: token,
        tokenAmount: _tokenAmountToBigInt(token, tokenAmount),
        wincAmount: wincAmount,
        creditsDisplay: creditsDisplay,
        estimatedStorageGiB: estimatedStorageGiB,
        usdValue: usdValue,
        adjustment: adjustment,
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );
    } catch (e) {
      logger.e('Error getting quote: $e');
      rethrow;
    }
  }

  /// Get winc amount for 1 GiB of storage (for price calculation).
  Future<BigInt> getWincForOneGiB() async {
    ensureSDKAvailable();

    try {
      // Use AR token for base pricing
      final client = await _getUnauthenticatedClient(CryptoToken.arioAO);

      // Get rate info - this gives us fiat to winc conversion
      final result = callMethod(client, 'getFiatRates', []);
      final ratesResult = await promiseToFuture(result);

      // Extract winc per GiB
      final wincPerGiB = getProperty(ratesResult, 'winc').toString();
      return BigInt.parse(wincPerGiB);
    } catch (e) {
      logger.e('Error getting winc for 1 GiB: $e');
      rethrow;
    }
  }

  // ============================================
  // Payment Execution
  // ============================================

  /// Execute a top-up payment with the given token.
  ///
  /// Returns the transaction ID on success.
  Future<String> executeTopUp({
    required CryptoToken token,
    required double tokenAmount,
    required Object signer,
  }) async {
    ensureSDKAvailable();

    try {
      final client = await _createAuthenticatedClient(token, signer);
      final tokenAmountObj = _convertTokenAmount(token, tokenAmount);

      final result = await topUpWithTokens(client, tokenAmountObj);

      // Extract transaction ID from result
      final txId = getProperty(result, 'id')?.toString();
      if (txId == null || txId.isEmpty) {
        throw TurboSDKException('No transaction ID returned');
      }

      logger.d('Top-up executed: $txId');
      return txId;
    } catch (e) {
      logger.e('Error executing top-up: $e');
      rethrow;
    }
  }

  /// Submit a transaction for retry/recovery.
  ///
  /// Use this when a transaction was submitted but confirmation failed.
  Future<void> submitTransaction({
    required CryptoToken token,
    required String transactionId,
    required Object signer,
  }) async {
    ensureSDKAvailable();

    try {
      final client = await _createAuthenticatedClient(token, signer);
      await submitFundTransaction(client, transactionId);

      logger.d('Transaction submitted for retry: $transactionId');
    } catch (e) {
      logger.e('Error submitting transaction: $e');
      rethrow;
    }
  }

  // ============================================
  // Balance
  // ============================================

  /// Get the current Turbo balance for an authenticated user.
  Future<BigInt> getBalance(Object signer) async {
    ensureSDKAvailable();

    try {
      final client = await _createAuthenticatedClient(CryptoToken.arioAO, signer);
      return await getTurboBalance(client);
    } catch (e) {
      logger.e('Error getting balance: $e');
      rethrow;
    }
  }

  // ============================================
  // Private Helpers
  // ============================================

  /// Get or create an unauthenticated client for the given token type.
  Future<Object> _getUnauthenticatedClient(CryptoToken token) async {
    final tokenType = token.turboTokenType;

    if (_unauthenticatedClients.containsKey(tokenType)) {
      return _unauthenticatedClients[tokenType]!;
    }

    final client = await createUnauthenticatedTurbo(
      paymentServiceUrl: _networkConfig.turboPaymentUrl,
      uploadServiceUrl: _networkConfig.turboUploadUrl,
      token: tokenType,
    );

    _unauthenticatedClients[tokenType] = client;
    return client;
  }

  /// Create an authenticated client for the given token and signer.
  Future<Object> _createAuthenticatedClient(
      CryptoToken token, Object signer) async {
    return await createAuthenticatedTurbo(
      signer: signer,
      paymentServiceUrl: _networkConfig.turboPaymentUrl,
      uploadServiceUrl: _networkConfig.turboUploadUrl,
      token: token.turboTokenType,
    );
  }

  /// Convert token amount to SDK-compatible format.
  Object _convertTokenAmount(CryptoToken token, double amount) {
    return switch (token) {
      CryptoToken.arioAO ||
      CryptoToken.arioAOViaEth ||
      CryptoToken.arioBase =>
        convertARIOToTokenAmount(amount),
      CryptoToken.ethBase || CryptoToken.ethL1 => convertETHToTokenAmount(amount),
      CryptoToken.sol => convertSOLToTokenAmount(amount),
      CryptoToken.usdcBase || CryptoToken.usdcEth =>
        // USDC uses 6 decimals, multiply by 1e6
        _createBigIntJS((amount * 1e6).toInt()),
    };
  }

  /// Convert token amount to BigInt for storage/comparison.
  BigInt _tokenAmountToBigInt(CryptoToken token, double amount) {
    final multiplier = switch (token.decimals) {
      6 => 1e6,
      9 => 1e9,
      18 => 1e18,
      _ => 1e6,
    };
    return BigInt.from((amount * multiplier).toInt());
  }

  /// Estimate USD value for a token amount.
  ///
  /// Estimates USD value for UI display purposes only.
  ///
  /// IMPORTANT: These are fallback estimates. The actual payment flow uses
  /// live prices from CoinGecko via CryptoPriceService.
  /// These values must match CryptoPriceService._defaultPrices for consistency.
  double _estimateUsdValue(CryptoToken token, double amount) {
    // Fallback prices - must match CryptoPriceService._defaultPrices
    final approximateUsdPrice = switch (token) {
      CryptoToken.arioAO ||
      CryptoToken.arioAOViaEth ||
      CryptoToken.arioBase =>
        0.005, // ARIO - matches CryptoPriceService fallback
      CryptoToken.ethBase || CryptoToken.ethL1 => 3000.0, // ETH
      CryptoToken.sol => 150.0, // SOL
      CryptoToken.usdcBase || CryptoToken.usdcEth => 1.0, // USDC
    };
    return amount * approximateUsdPrice;
  }

  /// Create a BigInt in JavaScript.
  Object _createBigIntJS(int value) {
    // Use dart:js_util to call BigInt constructor
    return callConstructor(
      getProperty(jsGlobalThis, 'BigInt'),
      [value],
    );
  }
}

/// Global reference to JavaScript's globalThis
@JS('globalThis')
external Object get _jsGlobalThis;

Object get jsGlobalThis => _jsGlobalThis;
