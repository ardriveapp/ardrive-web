// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:js_util';
import 'dart:typed_data';

import 'package:ardrive/utils/logger.dart';
import 'package:js/js.dart';

import '../solana_provider.dart';

@JS('globalThis')
external Object get _globalThis;

String? _activeProvider;

dynamic _callBridge(String method, List<dynamic> args) {
  final bridge = getProperty(_globalThis, 'CryptoWalletBridge');
  if (bridge == null) {
    throw Exception('CryptoWalletBridge not loaded');
  }
  return callMethod(bridge, method, args);
}

Future<dynamic> _callBridgeAsync(String method, List<dynamic> args) async {
  final result = _callBridge(method, args);
  if (result is Future || hasProperty(result, 'then')) {
    return await promiseToFuture(result);
  }
  return result;
}

bool isExtensionPresent() {
  try {
    final result = _callBridge('detectSolanaProviders', []);
    return getProperty(result, 'hasAnyProvider') ?? false;
  } catch (e) {
    logger.w('Error detecting Solana providers: $e');
    return false;
  }
}

SolanaLoginProviderDetection detectProviders() {
  try {
    final result = _callBridge('detectSolanaProviders', []);
    return SolanaLoginProviderDetection(
      hasAnyProvider: getProperty(result, 'hasAnyProvider') ?? false,
      hasPhantom: getProperty(result, 'phantom') ?? false,
      hasSolflare: getProperty(result, 'solflare') ?? false,
    );
  } catch (e) {
    logger.w('Error detecting Solana providers: $e');
    return const SolanaLoginProviderDetection();
  }
}

Future<SolanaConnection?> connect({String? provider}) async {
  try {
    final result = await _callBridgeAsync('connectSolanaWallet', [provider]);

    final address = getProperty(result, 'address') as String;
    final providerType = getProperty(result, 'providerType') as String;

    _activeProvider = providerType;

    logger.d('Connected to Solana wallet ($providerType): '
        '${address.substring(0, 6)}...');

    return SolanaConnection(
      address: address,
      providerType: providerType,
    );
  } catch (e) {
    final errorStr = e.toString();
    if (errorStr.contains('USER_REJECTED')) {
      logger.d('User rejected Solana wallet connection');
      return null;
    }
    logger.e('Error connecting to Solana wallet: $e');
    rethrow;
  }
}

Future<Uint8List> signMessage(String message) async {
  try {
    final result = await _callBridgeAsync(
      'signSolanaMessage',
      [_activeProvider, message],
    );

    // JS returns a Uint8Array which dart:js_util converts to a List
    final List<int> bytes;
    if (result is Uint8List) {
      bytes = result;
    } else {
      // Convert JS Uint8Array to Dart Uint8List
      final length = getProperty(result, 'length') as int;
      bytes = List<int>.generate(length, (i) => getProperty(result, i) as int);
    }

    return Uint8List.fromList(bytes);
  } catch (e) {
    final errorStr = e.toString();
    if (errorStr.contains('USER_REJECTED')) {
      throw Exception('User rejected signature request');
    }
    logger.e('Error signing message with Solana wallet: $e');
    rethrow;
  }
}

Future<void> disconnect() async {
  try {
    await _callBridgeAsync('disconnectSolanaWallet', [_activeProvider]);
    _activeProvider = null;
  } catch (e) {
    logger.w('Error disconnecting Solana wallet: $e');
  }
}
