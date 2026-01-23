// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:js_util';

import 'package:ardrive/turbo/config/crypto_network_config.dart';
import 'package:ardrive/turbo/services/crypto_price_service.dart';
import 'package:ardrive/turbo/services/ethereum_wallet_service.dart';
import 'package:ardrive/turbo/services/solana_wallet_service.dart';
import 'package:ardrive/turbo/services/turbo_sdk_interop.dart';
import 'package:ardrive/turbo/services/wallet_signer_cache.dart';
import 'package:ardrive/turbo/topup/models/crypto_payment_result.dart';
import 'package:ardrive/turbo/topup/models/crypto_quote.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/models/payment_model.dart';
import 'package:ardrive/turbo/topup/models/pending_transaction.dart';
import 'package:ardrive/turbo/topup/models/wallet_connection_state.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:js/js.dart';

/// Service for cryptocurrency payment operations.
///
/// Handles:
/// - Getting quotes for crypto top-ups
/// - Executing payments via the Turbo SDK
/// - Balance fetching for all supported tokens
/// - Gas estimation for EVM and Solana transactions
/// - Transaction retry/recovery
class CryptoPaymentService {
  final CryptoNetworkConfig _networkConfig;
  final ArDriveHTTP _httpClient;
  final WalletSignerCache _signerCache;
  final CryptoPriceService _priceService;

  /// Cached winc per GiB for storage calculations
  BigInt? _wincPerGiB;
  DateTime? _wincPerGiBCacheTime;
  static const _wincPerGiBCacheDuration = Duration(minutes: 5);

  CryptoPaymentService({
    required CryptoNetworkConfig networkConfig,
    required ArDriveHTTP httpClient,
    required WalletSignerCache signerCache,
    CryptoPriceService? priceService,
  })  : _networkConfig = networkConfig,
        _httpClient = httpClient,
        _signerCache = signerCache,
        _priceService = priceService ?? CryptoPriceService(httpClient: httpClient);

  /// Payment service URL
  String get _paymentUrl => _networkConfig.turboPaymentUrl;

  // ============================================
  // Quote / Pricing
  // ============================================

  /// Get a quote for a cryptocurrency top-up.
  ///
  /// [token] - The token to pay with
  /// [usdAmount] - Amount in USD
  /// [promoCode] - Optional promo code for discount
  /// [destinationAddress] - Arweave address to credit
  Future<CryptoQuote> getQuote({
    required CryptoToken token,
    required double usdAmount,
    String? promoCode,
    String? destinationAddress,
  }) async {
    try {
      // Get price in winc for the USD amount
      final priceResult = await _getPriceForFiat(
        amount: usdAmount,
        currency: 'usd',
        promoCode: promoCode,
        destinationAddress: destinationAddress,
      );

      // Get token amount needed for this USD value
      final tokenAmount = await _getTokenAmountForUsd(token, usdAmount);

      // Get winc per GiB for storage calculation
      final wincPerGiB = await _getWincPerGiB();

      // Calculate storage estimate
      final storageGiB = priceResult.winc.toDouble() / wincPerGiB.toDouble();

      // Parse adjustment if present
      Adjustment? adjustment;
      if (priceResult.adjustments.isNotEmpty) {
        adjustment = priceResult.adjustments.first;
      }

      return CryptoQuote(
        token: token,
        tokenAmount: tokenAmount,
        wincAmount: priceResult.winc,
        creditsDisplay: priceResult.winc.toDouble() / 1e12,
        estimatedStorageGiB: storageGiB,
        usdValue: usdAmount,
        adjustment: adjustment,
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        originalCreditsDisplay: adjustment != null
            ? (priceResult.quotedPaymentAmount ?? usdAmount) *
                (priceResult.winc.toDouble() /
                    (priceResult.actualPaymentAmount ?? usdAmount * 100)) /
                1e12
            : null,
      );
    } catch (e) {
      logger.e('Error getting crypto quote: $e');
      rethrow;
    }
  }

  /// Get quote by token amount (instead of USD amount)
  ///
  /// Uses token-specific pricing endpoint to get accurate pricing
  /// including token-specific benefits (e.g., ARIO has no fees).
  Future<CryptoQuote> getQuoteByTokenAmount({
    required CryptoToken token,
    required double tokenAmount,
    String? promoCode,
    String? destinationAddress,
  }) async {
    try {
      // Convert display amount to smallest unit (e.g., mARIO, wei, lamports)
      final tokenAmountSmallestUnit = _tokenAmountToBigInt(token, tokenAmount);

      // Use token-specific pricing endpoint for accurate pricing
      // This properly accounts for token-specific benefits (e.g., ARIO no fees)
      final priceResult = await _getPriceForToken(
        token: token,
        tokenAmount: tokenAmountSmallestUnit,
        promoCode: promoCode,
        destinationAddress: destinationAddress,
      );

      // Get winc per GiB for storage calculation
      final wincPerGiB = await _getWincPerGiB();

      // Calculate storage estimate
      final storageGiB = priceResult.winc.toDouble() / wincPerGiB.toDouble();

      // Parse adjustment if present
      Adjustment? adjustment;
      if (priceResult.adjustments.isNotEmpty) {
        adjustment = priceResult.adjustments.first;
      }

      // Estimate USD value for display purposes
      final usdValue = await _priceService.tokenToUsd(token, tokenAmount);

      return CryptoQuote(
        token: token,
        tokenAmount: tokenAmountSmallestUnit,
        wincAmount: priceResult.winc,
        creditsDisplay: priceResult.winc.toDouble() / 1e12,
        estimatedStorageGiB: storageGiB,
        usdValue: usdValue,
        adjustment: adjustment,
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
        originalCreditsDisplay: adjustment != null
            ? priceResult.winc.toDouble() /
                (1 - (adjustment.discountPercentage / 100)) /
                1e12
            : null,
      );
    } catch (e) {
      logger.e('Error getting quote by token amount: $e');
      rethrow;
    }
  }

  /// Validate a promo code
  Future<PromoCodeValidation> validatePromoCode({
    required String code,
    required double usdAmount,
    String? destinationAddress,
  }) async {
    try {
      final result = await _getPriceForFiat(
        amount: usdAmount,
        currency: 'usd',
        promoCode: code,
        destinationAddress: destinationAddress,
      );

      if (result.adjustments.isEmpty) {
        return PromoCodeValidation(
          isValid: false,
          errorMessage: 'Promo code not applicable',
        );
      }

      final adjustment = result.adjustments.first;
      return PromoCodeValidation(
        isValid: true,
        discountPercent: adjustment.discountPercentage,
        adjustmentName: adjustment.name,
      );
    } on CryptoPaymentException catch (e) {
      if (e.isInvalidPromoCode) {
        return PromoCodeValidation(
          isValid: false,
          errorMessage: 'Invalid or expired promo code',
        );
      }
      rethrow;
    }
  }

  // ============================================
  // Payment Execution
  // ============================================

  /// Execute a cryptocurrency payment.
  ///
  /// This is the main payment method that handles all token types.
  Future<CryptoPaymentResult> executePayment({
    required CryptoToken token,
    required CryptoQuote quote,
    required String arweaveAddress,
    EthereumWalletService? ethereumWallet,
    SolanaWalletService? solanaWallet,
  }) async {
    // Validate quote hasn't expired
    if (quote.isExpired) {
      return CryptoPaymentResult.failure(
        status: CryptoPaymentStatus.quoteExpired,
        token: token,
      );
    }

    try {
      final txId = await _executePaymentForToken(
        token: token,
        quote: quote,
        arweaveAddress: arweaveAddress,
        ethereumWallet: ethereumWallet,
        solanaWallet: solanaWallet,
      );

      logger.d('Payment executed successfully: $txId');

      return CryptoPaymentResult.pending(
        transactionId: txId,
        token: token,
      );
    } on EthereumWalletException catch (e) {
      logger.e('Ethereum wallet error during payment: $e');
      if (e.isUserRejected) {
        return CryptoPaymentResult.failure(
          status: CryptoPaymentStatus.userRejected,
          token: token,
        );
      }
      return CryptoPaymentResult.failure(
        status: CryptoPaymentStatus.failed,
        errorMessage: e.userMessage,
        token: token,
      );
    } on SolanaWalletException catch (e) {
      logger.e('Solana wallet error during payment: $e');
      if (e.isUserRejected) {
        return CryptoPaymentResult.failure(
          status: CryptoPaymentStatus.userRejected,
          token: token,
        );
      }
      return CryptoPaymentResult.failure(
        status: CryptoPaymentStatus.failed,
        errorMessage: e.userMessage,
        token: token,
      );
    } catch (e) {
      logger.e('Error executing payment: $e');
      return CryptoPaymentResult.failure(
        status: CryptoPaymentStatus.failed,
        errorMessage: e.toString(),
        token: token,
      );
    }
  }

  /// Submit a pending transaction for retry/recovery.
  ///
  /// Use this when a transaction was submitted but we couldn't confirm
  /// the credits were received. Uses the Turbo SDK's submitFundTransaction.
  Future<CryptoPaymentResult> submitPendingTransaction(
    PendingCryptoTransaction pendingTx, {
    EthereumWalletService? ethereumWallet,
    SolanaWalletService? solanaWallet,
  }) async {
    try {
      // Wait 3 seconds for block inclusion (as per spec)
      await Future.delayed(const Duration(seconds: 3));

      // Get the appropriate signer for the token type
      Object? signer;
      if (pendingTx.token.walletType == WalletType.ethereum && ethereumWallet != null) {
        final chainId = _networkConfig.getChainIdForToken(pendingTx.token);
        if (chainId != null) {
          signer = await _signerCache.getOrCreateEthereumSigner(ethereumWallet, chainId);
        }
      } else if (pendingTx.token.walletType == WalletType.solana && solanaWallet != null) {
        signer = await _signerCache.getOrCreateSolanaSigner(solanaWallet);
      } else if (pendingTx.token.walletType == WalletType.arweave) {
        final arweaveWallet = getProperty(_globalThis, 'arweaveWallet');
        if (arweaveWallet != null) {
          signer = ArconnectSignerJS(arweaveWallet);
        }
      }

      if (signer == null) {
        return CryptoPaymentResult.failure(
          status: CryptoPaymentStatus.failed,
          transactionId: pendingTx.transactionId,
          errorMessage: 'Could not get wallet signer for retry',
          token: pendingTx.token,
        );
      }

      // Create authenticated Turbo client and submit the transaction
      final turbo = await createAuthenticatedTurbo(
        signer: signer,
        paymentServiceUrl: _paymentUrl,
        token: pendingTx.token.turboTokenType,
      );

      await submitFundTransaction(turbo, pendingTx.transactionId);

      // If we get here, the submission was successful
      return CryptoPaymentResult.success(
        transactionId: pendingTx.transactionId,
        token: pendingTx.token,
        creditsAdded: pendingTx.expectedCredits ?? 0,
        newBalance: 0, // Will be refreshed separately
      );
    } on ArDriveHTTPException catch (e) {
      logger.e('HTTP error submitting pending transaction: $e');
      if (e.statusCode == 404) {
        return CryptoPaymentResult.failure(
          status: CryptoPaymentStatus.confirmationTimeout,
          transactionId: pendingTx.transactionId,
          errorMessage: 'Transaction not confirmed yet. Please wait and try again.',
          token: pendingTx.token,
        );
      }
      return CryptoPaymentResult.failure(
        status: CryptoPaymentStatus.failed,
        transactionId: pendingTx.transactionId,
        errorMessage: 'Failed to verify transaction',
        token: pendingTx.token,
      );
    } catch (e) {
      logger.e('Error submitting pending transaction: $e');
      return CryptoPaymentResult.failure(
        status: CryptoPaymentStatus.networkError,
        transactionId: pendingTx.transactionId,
        errorMessage: e.toString(),
        token: pendingTx.token,
      );
    }
  }

  // ============================================
  // Balance Fetching
  // ============================================

  /// Get token balance for a connected wallet.
  Future<TokenBalance> getTokenBalance({
    required CryptoToken token,
    EthereumWalletService? ethereumWallet,
    SolanaWalletService? solanaWallet,
    String? arweaveAddress,
  }) async {
    try {
      switch (token.walletType) {
        case WalletType.arweave:
          if (arweaveAddress == null) {
            return TokenBalance.error(token, 'Arweave address required');
          }
          return _getArioAOBalance(arweaveAddress);

        case WalletType.ethereum:
          if (ethereumWallet == null || !ethereumWallet.isConnected) {
            return TokenBalance.error(token, 'Ethereum wallet not connected');
          }
          return ethereumWallet.getTokenBalance(token);

        case WalletType.solana:
          if (solanaWallet == null || !solanaWallet.isConnected) {
            return TokenBalance.error(token, 'Solana wallet not connected');
          }
          return solanaWallet.getTokenBalance();
      }
    } catch (e) {
      logger.e('Error getting token balance: $e');
      return TokenBalance.error(token, e.toString());
    }
  }

  /// Get ARIO balance on AO network.
  Future<TokenBalance> _getArioAOBalance(String arweaveAddress) async {
    try {
      // Use the ar.io SDK to get ARIO balance via the global getARIOTokens function
      // This is loaded via ario_sdk.min.js and exposed as window.getARIOTokens
      final getARIOTokens = getProperty(_globalThis, 'getARIOTokens');
      if (getARIOTokens == null) {
        logger.w('getARIOTokens not found on window');
        return TokenBalance.error(
          CryptoToken.arioAO,
          'ARIO SDK not loaded',
        );
      }

      final result = callMethod(_globalThis, 'getARIOTokens', [arweaveAddress]);
      final balanceStr = await promiseToFuture(result) as String;

      // The result might be "null" string if no balance
      if (balanceStr == 'null' || balanceStr.isEmpty) {
        return TokenBalance(
          token: CryptoToken.arioAO,
          rawBalance: BigInt.zero,
          lastUpdated: DateTime.now(),
        );
      }

      // Balance is returned in mARIO (smallest unit, 6 decimals)
      // So 1 ARIO = 1,000,000 mARIO
      final balance = BigInt.parse(balanceStr);

      return TokenBalance(
        token: CryptoToken.arioAO,
        rawBalance: balance,
        lastUpdated: DateTime.now(),
      );
    } catch (e) {
      logger.e('Error getting ARIO balance: $e');
      return TokenBalance.error(CryptoToken.arioAO, e.toString());
    }
  }

  // ============================================
  // Gas Estimation
  // ============================================

  /// Estimate network fee for a payment.
  ///
  /// Returns the estimated fee in USD.
  Future<double> estimateNetworkFee({
    required CryptoToken token,
    EthereumWalletService? ethereumWallet,
  }) async {
    // ARIO on AO has no gas fees
    if (token.isAOToken) {
      return 0;
    }

    if (!token.requiresGasEstimation) {
      return 0;
    }

    try {
      if (token.walletType == WalletType.ethereum && ethereumWallet != null) {
        return ethereumWallet.estimateNetworkFeeUsd(token);
      }

      if (token.walletType == WalletType.solana) {
        // Solana fees are typically very low (~$0.001)
        return 0.01;
      }

      return 0;
    } catch (e) {
      logger.w('Error estimating network fee: $e');
      return 0;
    }
  }

  // ============================================
  // Private Payment Execution Methods
  // ============================================

  Future<String> _executePaymentForToken({
    required CryptoToken token,
    required CryptoQuote quote,
    required String arweaveAddress,
    EthereumWalletService? ethereumWallet,
    SolanaWalletService? solanaWallet,
  }) async {
    switch (token) {
      case CryptoToken.arioAO:
        return _executeArioAOPayment(quote, arweaveAddress);

      case CryptoToken.arioAOViaEth:
        if (ethereumWallet == null) {
          throw CryptoPaymentException('Ethereum wallet required');
        }
        return _executeArioAOViaEthPayment(quote, arweaveAddress, ethereumWallet);

      case CryptoToken.arioBase:
      case CryptoToken.usdcBase:
      case CryptoToken.ethBase:
      case CryptoToken.usdcEth:
      case CryptoToken.ethL1:
        if (ethereumWallet == null) {
          throw CryptoPaymentException('Ethereum wallet required');
        }
        return _executeEvmPayment(token, quote, arweaveAddress, ethereumWallet);

      case CryptoToken.sol:
        if (solanaWallet == null) {
          throw CryptoPaymentException('Solana wallet required');
        }
        return _executeSolanaPayment(quote, arweaveAddress, solanaWallet);
    }
  }

  /// Execute ARIO on AO payment using ArConnect wallet.
  Future<String> _executeArioAOPayment(
    CryptoQuote quote,
    String arweaveAddress,
  ) async {
    // Use the existing ArConnect signer
    final arweaveWallet = getProperty(_globalThis, 'arweaveWallet');
    if (arweaveWallet == null) {
      throw CryptoPaymentException('ArConnect wallet not available');
    }

    // Create ArconnectSigner
    final signer = ArconnectSignerJS(arweaveWallet);

    // Create authenticated Turbo client
    final turbo = await createAuthenticatedTurbo(
      signer: signer,
      paymentServiceUrl: _paymentUrl,
      token: 'ario',
    );

    // Convert token amount
    final tokenAmount = convertARIOToTokenAmount(quote.tokenAmountDisplay);

    // Execute top-up with destination address
    final result = await topUpWithTokens(
      turbo,
      tokenAmount,
      destinationAddress: arweaveAddress,
    );
    final txId = getProperty(result, 'id')?.toString();

    if (txId == null || txId.isEmpty) {
      throw CryptoPaymentException('No transaction ID returned');
    }

    return txId;
  }

  /// Execute ARIO on AO payment via Ethereum wallet (InjectedEthereumSigner).
  Future<String> _executeArioAOViaEthPayment(
    CryptoQuote quote,
    String arweaveAddress,
    EthereumWalletService ethereumWallet,
  ) async {
    // Get or create the AO signature
    final aoSignature = await _signerCache.signAndCacheAOConnect(ethereumWallet);

    // Get ethers provider and signer
    final bridge = getProperty(_globalThis, 'CryptoWalletBridge');
    final provider = callMethod(bridge, 'getEthereumProvider', [null]);

    // Create InjectedEthereumSigner with the derived public key
    final signer = InjectedEthereumSignerJS(provider);

    // Set the public key (derived from signature)
    final ethers = getProperty(_globalThis, 'ethers');
    final publicKeyBytes = callMethod(ethers, 'getBytes', [aoSignature.publicKey]);
    signer.publicKey = publicKeyBytes;

    // Create authenticated Turbo client
    final turbo = await createAuthenticatedTurbo(
      signer: signer,
      paymentServiceUrl: _paymentUrl,
      token: 'ario',
    );

    // Convert token amount
    final tokenAmount = convertARIOToTokenAmount(quote.tokenAmountDisplay);

    // Execute top-up with destination address
    final result = await topUpWithTokens(
      turbo,
      tokenAmount,
      destinationAddress: arweaveAddress,
    );
    final txId = getProperty(result, 'id')?.toString();

    if (txId == null || txId.isEmpty) {
      throw CryptoPaymentException('No transaction ID returned');
    }

    return txId;
  }

  /// Execute EVM token payment (ETH, USDC, ARIO on Base/Ethereum).
  ///
  /// For EVM token transfers, we use the walletAdapter pattern:
  /// `walletAdapter: { getSigner: () => ethersSigner }`
  /// This allows the SDK to manage transaction signing internally.
  Future<String> _executeEvmPayment(
    CryptoToken token,
    CryptoQuote quote,
    String arweaveAddress,
    EthereumWalletService ethereumWallet,
  ) async {
    // Ensure we're on the correct chain
    await ethereumWallet.ensureCorrectChain(token);

    // Get ethers.js signer for the wallet adapter
    final chainId = _networkConfig.getChainIdForToken(token)!;
    final ethersSigner = await _signerCache.getOrCreateEthereumSigner(
      ethereumWallet,
      chainId,
    );

    // Create authenticated Turbo client with wallet adapter pattern
    // EVM payments use walletAdapter: { getSigner: () => signer }
    final turbo = await createAuthenticatedTurboWithWalletAdapter(
      ethersSigner: ethersSigner,
      paymentServiceUrl: _paymentUrl,
      token: token.turboTokenType,
    );

    // Convert token amount based on type
    final tokenAmount = _convertTokenAmountForSDK(token, quote.tokenAmountDisplay);

    // Execute top-up with destination address
    final result = await topUpWithTokens(
      turbo,
      tokenAmount,
      destinationAddress: arweaveAddress,
    );
    final txId = getProperty(result, 'id')?.toString();

    if (txId == null || txId.isEmpty) {
      throw CryptoPaymentException('No transaction ID returned');
    }

    return txId;
  }

  /// Execute Solana SOL payment.
  ///
  /// For Solana payments, we use the walletAdapter pattern:
  /// `walletAdapter: window.solana`
  /// The SDK expects the raw Solana wallet provider (Phantom/Solflare).
  Future<String> _executeSolanaPayment(
    CryptoQuote quote,
    String arweaveAddress,
    SolanaWalletService solanaWallet,
  ) async {
    // Get the Solana wallet adapter (window.solana)
    final walletAdapter = await _signerCache.getOrCreateSolanaSigner(solanaWallet);

    // Create authenticated Turbo client with Solana wallet adapter
    final turbo = await createAuthenticatedTurboWithSolanaAdapter(
      solanaWalletAdapter: walletAdapter,
      paymentServiceUrl: _paymentUrl,
    );

    // Convert token amount
    final tokenAmount = convertSOLToTokenAmount(quote.tokenAmountDisplay);

    // Execute top-up with destination address
    final result = await topUpWithTokens(
      turbo,
      tokenAmount,
      destinationAddress: arweaveAddress,
    );
    final txId = getProperty(result, 'id')?.toString();

    if (txId == null || txId.isEmpty) {
      throw CryptoPaymentException('No transaction ID returned');
    }

    return txId;
  }

  // ============================================
  // Private Helpers
  // ============================================

  Future<_PriceForFiatResult> _getPriceForFiat({
    required double amount,
    required String currency,
    String? promoCode,
    String? destinationAddress,
  }) async {
    final params = <String, String>{};
    if (promoCode != null && promoCode.isNotEmpty) {
      params['promoCode'] = promoCode;
    }
    if (destinationAddress != null) {
      params['destinationAddress'] = destinationAddress;
    }

    final queryString = params.isEmpty
        ? ''
        : '?${params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';

    try {
      final result = await _httpClient.get(
        url: '$_paymentUrl/v1/price/$currency/$amount$queryString',
      );

      final data = jsonDecode(result.data);
      final winc = BigInt.parse(data['winc']);
      // API may return these as strings or ints, so parse safely
      final actualPaymentAmount = data['actualPaymentAmount'] != null
          ? int.tryParse(data['actualPaymentAmount'].toString())
          : null;
      final quotedPaymentAmount = data['quotedPaymentAmount'] != null
          ? int.tryParse(data['quotedPaymentAmount'].toString())
          : null;
      final adjustments = ((data['adjustments'] ?? []) as List)
          .map((e) => Adjustment.fromJson(e))
          .toList();

      return _PriceForFiatResult(
        winc: winc,
        actualPaymentAmount: actualPaymentAmount,
        quotedPaymentAmount: quotedPaymentAmount,
        adjustments: adjustments,
      );
    } on ArDriveHTTPException catch (e) {
      if (e.statusCode == 400) {
        // Check the actual error response
        final errorMessage = e.data?.toString() ?? '';

        // Only treat as promo code error if there's actually a promo code
        // and the error mentions it
        if (promoCode != null &&
            promoCode.isNotEmpty &&
            (errorMessage.toLowerCase().contains('promo') ||
                errorMessage.toLowerCase().contains('coupon') ||
                errorMessage.toLowerCase().contains('code'))) {
          throw CryptoPaymentException.invalidPromoCode(promoCode);
        }

        // Log and throw general error
        logger.e('API returned 400: $errorMessage');
        throw CryptoPaymentException(
          errorMessage.isNotEmpty ? errorMessage : 'Bad request',
        );
      }
      rethrow;
    }
  }

  /// Get price for a specific token amount using token-specific endpoint.
  ///
  /// This endpoint properly accounts for token-specific pricing benefits
  /// (e.g., ARIO has no fees, giving more credits than USD equivalent).
  ///
  /// Endpoint: GET /v1/price/{tokenType}/{tokenAmount}
  /// Where tokenAmount is in the smallest unit (mARIO, wei, lamports, etc.)
  Future<_PriceForFiatResult> _getPriceForToken({
    required CryptoToken token,
    required BigInt tokenAmount,
    String? promoCode,
    String? destinationAddress,
  }) async {
    final tokenType = token.turboTokenType;

    final params = <String, String>{};
    if (promoCode != null && promoCode.isNotEmpty) {
      params['promoCode'] = promoCode;
    }
    if (destinationAddress != null) {
      params['destinationAddress'] = destinationAddress;
    }

    final queryString = params.isEmpty
        ? ''
        : '?${params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';

    try {
      final result = await _httpClient.get(
        url: '$_paymentUrl/v1/price/$tokenType/$tokenAmount$queryString',
      );

      final data = jsonDecode(result.data);
      final winc = BigInt.parse(data['winc']);
      // API may return these as strings or ints, so parse safely
      final actualPaymentAmount = data['actualPaymentAmount'] != null
          ? int.tryParse(data['actualPaymentAmount'].toString())
          : null;
      final quotedPaymentAmount = data['quotedPaymentAmount'] != null
          ? int.tryParse(data['quotedPaymentAmount'].toString())
          : null;
      final adjustments = ((data['adjustments'] ?? []) as List)
          .map((e) => Adjustment.fromJson(e))
          .toList();

      return _PriceForFiatResult(
        winc: winc,
        actualPaymentAmount: actualPaymentAmount,
        quotedPaymentAmount: quotedPaymentAmount,
        adjustments: adjustments,
      );
    } on ArDriveHTTPException catch (e) {
      if (e.statusCode == 400) {
        // Check the actual error response
        final errorMessage = e.data?.toString() ?? '';

        // Only treat as promo code error if there's actually a promo code
        // and the error mentions it
        if (promoCode != null &&
            promoCode.isNotEmpty &&
            (errorMessage.toLowerCase().contains('promo') ||
                errorMessage.toLowerCase().contains('coupon') ||
                errorMessage.toLowerCase().contains('code'))) {
          throw CryptoPaymentException.invalidPromoCode(promoCode);
        }

        // Log and throw general error
        logger.e('API returned 400: $errorMessage');
        throw CryptoPaymentException(
          errorMessage.isNotEmpty ? errorMessage : 'Bad request',
        );
      }
      rethrow;
    }
  }

  Future<BigInt> _getWincPerGiB() async {
    // Check cache
    if (_wincPerGiB != null &&
        _wincPerGiBCacheTime != null &&
        DateTime.now().difference(_wincPerGiBCacheTime!) < _wincPerGiBCacheDuration) {
      return _wincPerGiB!;
    }

    try {
      final result = await _httpClient.get(
        url: '$_paymentUrl/v1/price/bytes/${1024 * 1024 * 1024}', // 1 GiB
      );

      final data = jsonDecode(result.data);
      _wincPerGiB = BigInt.parse(data['winc']);
      _wincPerGiBCacheTime = DateTime.now();

      return _wincPerGiB!;
    } catch (e) {
      logger.e('Error getting winc per GiB: $e');
      // Return a reasonable default
      return BigInt.from(1e12); // 1 credit per GiB as fallback
    }
  }

  Future<BigInt> _getTokenAmountForUsd(CryptoToken token, double usdAmount) async {
    // Use the price service to get live token prices
    final tokenAmount = await _priceService.usdToToken(token, usdAmount);
    return _tokenAmountToBigInt(token, tokenAmount);
  }

  /// Get the current USD price per token (public for display purposes)
  Future<double> getTokenPrice(CryptoToken token) async {
    return _priceService.getUsdPrice(token);
  }

  /// Convert token amount to USD value
  Future<double> tokenToUsd(CryptoToken token, double tokenAmount) async {
    return _priceService.tokenToUsd(token, tokenAmount);
  }

  /// Convert USD amount to token amount
  Future<double> usdToToken(CryptoToken token, double usdAmount) async {
    return _priceService.usdToToken(token, usdAmount);
  }

  /// Refresh price cache
  Future<void> refreshPrices() async {
    await _priceService.refreshPrices();
  }

  BigInt _tokenAmountToBigInt(CryptoToken token, double amount) {
    final multiplier = switch (token.decimals) {
      6 => 1e6,
      9 => 1e9,
      18 => 1e18,
      _ => 1e6,
    };
    return BigInt.from((amount * multiplier).toInt());
  }

  Object _convertTokenAmountForSDK(CryptoToken token, double amount) {
    return switch (token) {
      CryptoToken.arioAO ||
      CryptoToken.arioAOViaEth ||
      CryptoToken.arioBase =>
        convertARIOToTokenAmount(amount),
      CryptoToken.ethBase || CryptoToken.ethL1 => convertETHToTokenAmount(amount),
      CryptoToken.sol => convertSOLToTokenAmount(amount),
      CryptoToken.usdcBase || CryptoToken.usdcEth =>
        // USDC: multiply by 1e6 directly
        _createBigIntJS((amount * 1e6).toInt()),
    };
  }

  Object _createBigIntJS(int value) {
    return callConstructor(
      getProperty(_globalThis, 'BigInt'),
      [value],
    );
  }
}

/// Global reference to JavaScript's globalThis
@JS('globalThis')
external Object get _globalThis;

/// Internal result class for fiat price query
class _PriceForFiatResult {
  final BigInt winc;
  final int? actualPaymentAmount;
  final int? quotedPaymentAmount;
  final List<Adjustment> adjustments;

  _PriceForFiatResult({
    required this.winc,
    this.actualPaymentAmount,
    this.quotedPaymentAmount,
    required this.adjustments,
  });
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
