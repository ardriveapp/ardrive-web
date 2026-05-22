// ignore_for_file: avoid_web_libraries_in_flutter

/// JavaScript interop for @ardrive/turbo-sdk
///
/// This file provides Dart bindings to the Turbo SDK loaded via index.html.
/// The SDK is loaded as a module and exposes functions on the window object.
@JS()
library turbo_sdk;

import 'dart:js_util';

import 'package:js/js.dart';

import '../turbo_sdk_types.dart';

// ============================================
// SDK Load Status
// ============================================

/// Check if the Turbo SDK has been loaded successfully
@JS('TurboSDKLoaded')
external bool? get _turboSDKLoaded;

/// Get any error message from SDK loading
@JS('TurboSDKError')
external String? get _turboSDKError;

/// Whether the SDK is loaded and ready to use
bool get isTurboSDKLoaded => _turboSDKLoaded == true;

/// Error message if SDK failed to load
String? get turboSDKError => _turboSDKError;

// ============================================
// TurboFactory
// ============================================

@JS('TurboFactory')
class TurboFactoryJS {
  /// Create an unauthenticated Turbo client for public operations (pricing)
  external static Object unauthenticated(Object? config);

  /// Create an authenticated Turbo client for payment operations
  external static Object authenticated(Object config);
}

// ============================================
// Token Amount Conversion Functions
// ============================================

/// Convert AR to winston (smallest unit)
@JS('ARToTokenAmount')
external Object arToTokenAmount(num amount);

/// Convert ARIO to mARIO (smallest unit)
@JS('ARIOToTokenAmount')
external Object arIOToTokenAmount(num amount);

/// Convert ETH to wei (smallest unit)
@JS('ETHToTokenAmount')
external Object ethToTokenAmount(num amount);

/// Convert SOL to lamports (smallest unit)
@JS('SOLToTokenAmount')
external Object solToTokenAmount(num amount);

// ============================================
// Configuration Objects
// ============================================

@JS()
@anonymous
class TurboConfigJS {
  external factory TurboConfigJS({
    String? gatewayUrl,
    String? paymentServiceUrl,
    String? uploadServiceUrl,
    String? token,
  });

  external String? get gatewayUrl;
  external String? get paymentServiceUrl;
  external String? get uploadServiceUrl;
  external String? get token;
}

@JS()
@anonymous
class ServiceConfigJS {
  external factory ServiceConfigJS({
    String? url,
  });

  external String? get url;
}

@JS()
@anonymous
class TurboAuthConfigJS {
  external factory TurboAuthConfigJS({
    Object? signer,
    Object? walletAdapter,
    String? gatewayUrl,
    Object? paymentServiceConfig,
    Object? uploadServiceConfig,
    String? token,
  });

  external Object? get signer;
  external Object? get walletAdapter;
  external String? get gatewayUrl;
  external Object? get paymentServiceConfig;
  external Object? get uploadServiceConfig;
  external String? get token;
}

/// Wallet adapter config for EVM token transfers
/// The SDK expects { getSigner: () => ethersSigner } for EVM payments
@JS()
@anonymous
class WalletAdapterConfigJS {
  external factory WalletAdapterConfigJS({
    Object getSigner,
  });

  external Object get getSigner;
}

@JS()
@anonymous
class TopUpWithTokensParamsJS {
  external factory TopUpWithTokensParamsJS({
    Object tokenAmount,
    Object? feeMultiplier,
    String? turboCreditDestinationAddress,
  });

  external Object get tokenAmount;
  external Object? get feeMultiplier;
  external String? get turboCreditDestinationAddress;
}

@JS()
@anonymous
class GetWincForTokenParamsJS {
  external factory GetWincForTokenParamsJS({
    Object tokenAmount,
  });

  external Object get tokenAmount;
}

// ============================================
// Signer Classes
// ============================================

@JS('ArconnectSigner')
class ArconnectSignerJS {
  external ArconnectSignerJS(Object arweaveWallet);
}

@JS('InjectedEthereumSigner')
class InjectedEthereumSignerJS {
  external InjectedEthereumSignerJS(Object provider);
  external Object? get publicKey;
  external set publicKey(Object? value);
}

// ============================================
// Helper Functions for Type-Safe Dart Calls
// ============================================

/// Create an unauthenticated Turbo client
Future<Object> createUnauthenticatedTurbo({
  String? gatewayUrl,
  String? paymentServiceUrl,
  String? uploadServiceUrl,
  String? token,
}) async {
  await ensureSDKLoaded();

  final config = TurboConfigJS(
    gatewayUrl: gatewayUrl,
    paymentServiceUrl: paymentServiceUrl,
    uploadServiceUrl: uploadServiceUrl,
    token: token,
  );

  return TurboFactoryJS.unauthenticated(config);
}

/// Create an authenticated Turbo client with a signer
///
/// Use this for:
/// - ARIO on AO (ArconnectSigner)
/// - ARIO on AO via ETH (InjectedEthereumSigner)
Future<Object> createAuthenticatedTurbo({
  required Object signer,
  String? gatewayUrl,
  String? paymentServiceUrl,
  String? uploadServiceUrl,
  String? token,
}) async {
  await ensureSDKLoaded();

  // Build service config objects as expected by the SDK
  final paymentServiceConfig = paymentServiceUrl != null
      ? ServiceConfigJS(url: paymentServiceUrl)
      : null;
  final uploadServiceConfig =
      uploadServiceUrl != null ? ServiceConfigJS(url: uploadServiceUrl) : null;

  final config = TurboAuthConfigJS(
    signer: signer,
    gatewayUrl: gatewayUrl,
    paymentServiceConfig: paymentServiceConfig,
    uploadServiceConfig: uploadServiceConfig,
    token: token,
  );

  return TurboFactoryJS.authenticated(config);
}

/// Create an authenticated Turbo client with a wallet adapter
///
/// Use this for EVM token transfers (ETH, USDC, ARIO on Base/Ethereum).
/// The wallet adapter pattern is: { getSigner: () => ethersSigner }
/// This allows the SDK to manage transaction signing internally.
Future<Object> createAuthenticatedTurboWithWalletAdapter({
  required Object ethersSigner,
  String? gatewayUrl,
  String? paymentServiceUrl,
  String? uploadServiceUrl,
  required String token,
}) async {
  await ensureSDKLoaded();

  // Build service config objects as expected by the SDK
  final paymentServiceConfig = paymentServiceUrl != null
      ? ServiceConfigJS(url: paymentServiceUrl)
      : null;
  final uploadServiceConfig =
      uploadServiceUrl != null ? ServiceConfigJS(url: uploadServiceUrl) : null;

  // Create the walletAdapter with getSigner function
  // The SDK expects: { getSigner: () => ethersSigner }
  final walletAdapter = jsify({
    'getSigner': allowInterop(() => ethersSigner),
  });

  final config = TurboAuthConfigJS(
    walletAdapter: walletAdapter,
    gatewayUrl: gatewayUrl,
    paymentServiceConfig: paymentServiceConfig,
    uploadServiceConfig: uploadServiceConfig,
    token: token,
  );

  return TurboFactoryJS.authenticated(config);
}

/// Create an authenticated Turbo client with a Solana wallet adapter
///
/// Use this for Solana (SOL) payments.
/// The SDK expects the raw window.solana adapter object.
Future<Object> createAuthenticatedTurboWithSolanaAdapter({
  required Object solanaWalletAdapter,
  String? gatewayUrl,
  String? paymentServiceUrl,
  String? uploadServiceUrl,
}) async {
  await ensureSDKLoaded();

  // Build service config objects as expected by the SDK
  final paymentServiceConfig = paymentServiceUrl != null
      ? ServiceConfigJS(url: paymentServiceUrl)
      : null;
  final uploadServiceConfig =
      uploadServiceUrl != null ? ServiceConfigJS(url: uploadServiceUrl) : null;

  final config = TurboAuthConfigJS(
    walletAdapter: solanaWalletAdapter,
    gatewayUrl: gatewayUrl,
    paymentServiceConfig: paymentServiceConfig,
    uploadServiceConfig: uploadServiceConfig,
    token: 'solana',
  );

  return TurboFactoryJS.authenticated(config);
}

/// Get winc for a token amount
Future<BigInt> getWincForToken(Object turboClient, Object tokenAmount) async {
  final params = GetWincForTokenParamsJS(tokenAmount: tokenAmount);
  final result = callMethod(turboClient, 'getWincForToken', [params]);
  final wincResult = await promiseToFuture(result);

  // Extract winc string from result
  final wincString = getProperty(wincResult, 'winc').toString();
  return BigInt.parse(wincString);
}

/// Execute top up with tokens
Future<Object> topUpWithTokens(
  Object turboClient,
  Object tokenAmount, {
  Object? feeMultiplier,
  String? destinationAddress,
}) async {
  final params = TopUpWithTokensParamsJS(
    tokenAmount: tokenAmount,
    feeMultiplier: feeMultiplier,
    turboCreditDestinationAddress: destinationAddress,
  );
  final result = callMethod(turboClient, 'topUpWithTokens', [params]);
  return promiseToFuture(result);
}

/// Get the user's Turbo balance
Future<BigInt> getTurboBalance(Object turboClient) async {
  final result = callMethod(turboClient, 'getBalance', []);
  final balanceResult = await promiseToFuture(result);

  // Extract balance from result
  final wincString = getProperty(balanceResult, 'winc').toString();
  return BigInt.parse(wincString);
}

/// Submit a fund transaction for retry/recovery
Future<Object> submitFundTransaction(
    Object turboClient, String transactionId) async {
  final result =
      callMethod(turboClient, 'submitFundTransaction', [transactionId]);
  return promiseToFuture(result);
}

/// Convert token amounts using SDK helpers.
/// These assume ensureSDKLoaded() was already called earlier in the flow
/// (e.g., by createAuthenticatedTurbo or createUnauthenticatedTurbo).
Object convertARToTokenAmount(double amount) {
  return arToTokenAmount(amount);
}

Object convertARIOToTokenAmount(double amount) {
  return arIOToTokenAmount(amount);
}

Object convertETHToTokenAmount(double amount) {
  return ethToTokenAmount(amount);
}

Object convertSOLToTokenAmount(double amount) {
  return solToTokenAmount(amount);
}

/// Ensure the SDK is loaded before using it.
/// Lazily loads the Turbo SDK on first access.
Future<void> ensureSDKLoaded() async {
  if (isTurboSDKLoaded) return;

  // Trigger lazy load via LazyLoader
  try {
    final lazyLoader = getProperty(globalThis, 'LazyLoader');
    if (lazyLoader != null) {
      final promise = callMethod(lazyLoader, 'loadTurboSDK', []);
      await promiseToFuture(promise);
    }
  } catch (_) {
    // LazyLoader may not be available (non-web or test)
  }

  if (!isTurboSDKLoaded) {
    final error = turboSDKError ?? 'SDK not loaded';
    throw TurboSDKNotLoadedException(error);
  }
}

@JS('globalThis')
external Object get globalThis;

// Exceptions are defined in turbo_sdk_interop.dart
