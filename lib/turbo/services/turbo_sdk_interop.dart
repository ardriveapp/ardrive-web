// ignore_for_file: avoid_web_libraries_in_flutter

/// JavaScript interop for @ardrive/turbo-sdk
///
/// This file provides Dart bindings to the Turbo SDK loaded via index.html.
/// The SDK is loaded as a module and exposes functions on the window object.
@JS()
library turbo_sdk;

import 'dart:async';
import 'dart:js_util';

import 'package:js/js.dart';

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
class TurboAuthConfigJS {
  external factory TurboAuthConfigJS({
    Object signer,
    String? gatewayUrl,
    String? paymentServiceUrl,
    String? uploadServiceUrl,
    String? token,
  });

  external Object get signer;
  external String? get gatewayUrl;
  external String? get paymentServiceUrl;
  external String? get uploadServiceUrl;
  external String? get token;
}

@JS()
@anonymous
class TopUpWithTokensParamsJS {
  external factory TopUpWithTokensParamsJS({
    Object tokenAmount,
    Object? feeMultiplier,
  });

  external Object get tokenAmount;
  external Object? get feeMultiplier;
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
  _ensureSDKLoaded();

  final config = TurboConfigJS(
    gatewayUrl: gatewayUrl,
    paymentServiceUrl: paymentServiceUrl,
    uploadServiceUrl: uploadServiceUrl,
    token: token,
  );

  return TurboFactoryJS.unauthenticated(config);
}

/// Create an authenticated Turbo client
Future<Object> createAuthenticatedTurbo({
  required Object signer,
  String? gatewayUrl,
  String? paymentServiceUrl,
  String? uploadServiceUrl,
  String? token,
}) async {
  _ensureSDKLoaded();

  final config = TurboAuthConfigJS(
    signer: signer,
    gatewayUrl: gatewayUrl,
    paymentServiceUrl: paymentServiceUrl,
    uploadServiceUrl: uploadServiceUrl,
    token: token,
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
Future<Object> topUpWithTokens(Object turboClient, Object tokenAmount,
    {Object? feeMultiplier}) async {
  final params = TopUpWithTokensParamsJS(
    tokenAmount: tokenAmount,
    feeMultiplier: feeMultiplier,
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

/// Convert token amounts using SDK helpers
Object convertARToTokenAmount(double amount) {
  _ensureSDKLoaded();
  return arToTokenAmount(amount);
}

Object convertARIOToTokenAmount(double amount) {
  _ensureSDKLoaded();
  return arIOToTokenAmount(amount);
}

Object convertETHToTokenAmount(double amount) {
  _ensureSDKLoaded();
  return ethToTokenAmount(amount);
}

Object convertSOLToTokenAmount(double amount) {
  _ensureSDKLoaded();
  return solToTokenAmount(amount);
}

/// Ensure the SDK is loaded before using it
void _ensureSDKLoaded() {
  if (!isTurboSDKLoaded) {
    final error = turboSDKError ?? 'SDK not loaded';
    throw TurboSDKNotLoadedException(error);
  }
}

// ============================================
// Exceptions
// ============================================

class TurboSDKNotLoadedException implements Exception {
  final String message;

  TurboSDKNotLoadedException(this.message);

  @override
  String toString() => 'TurboSDKNotLoadedException: $message';
}

class TurboSDKException implements Exception {
  final String message;
  final Object? originalError;

  TurboSDKException(this.message, [this.originalError]);

  @override
  String toString() => 'TurboSDKException: $message';
}
