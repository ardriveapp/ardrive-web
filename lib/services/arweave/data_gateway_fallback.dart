import 'dart:async';

import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:arweave/arweave.dart';
import 'package:http/http.dart';

/// Provides data gateway fallback resilience.
///
/// When the primary gateway fails (404, 429, 5xx, timeout), automatically
/// tries gateways from the AR.IO GAR list, then arweave.net as last resort.
/// Fallback is per-request — the primary gateway is always tried first.
class DataGatewayFallback {
  final ArioSDK _arioSDK;
  final Map<String, Arweave> _clientCache = {};

  static const _lastResortGateway = 'https://arweave.net';
  static const _maxGarFallbacks = 2;
  static const _retryPerGateway = 1;
  static const _garListTimeout = Duration(seconds: 5);
  static const _requestTimeout = Duration(seconds: 5);
  /// Total time allowed for the entire fallback chain per tx.
  /// Prevents a single missing/broken tx from blocking sync for minutes.
  static const _totalFetchTimeout = Duration(seconds: 25);

  List<Gateway>? _cachedGateways;

  DataGatewayFallback({
    required ArioSDK arioSDK,
  }) : _arioSDK = arioSDK;

  /// Fetch transaction data with automatic gateway fallback.
  ///
  /// Tries: primary → up to 2 GAR gateways → arweave.net
  ///
  /// If ALL gateways return 404, throws [TransactionNotFound] to preserve
  /// upstream error handling (e.g. private drive detection during login).
  Future<Response> fetchData(String txId, Arweave primaryClient) async {
    return _fetchDataWithTimeout(txId, primaryClient)
        .timeout(_totalFetchTimeout, onTimeout: () {
      logger.w('Total fetch timeout exceeded for tx $txId');
      throw Exception('Total fetch timeout exceeded for tx $txId');
    });
  }

  Future<Response> _fetchDataWithTimeout(
      String txId, Arweave primaryClient) async {
    var all404 = true;

    // 1. Try primary gateway
    try {
      return await _tryGateway(primaryClient, txId);
    } on _ErrorFromStatus catch (e) {
      if (!e.retryable) rethrow;
      if (e.statusCode != 404) all404 = false;
      logger.w(
        'Primary gateway failed for tx $txId '
        '(${primaryClient.api.gatewayUrl}): $e',
      );
    } catch (e) {
      all404 = false;
      logger.w(
        'Primary gateway failed for tx $txId '
        '(${primaryClient.api.gatewayUrl}): $e',
      );
    }

    // 2. Try GAR gateways (cached to avoid repeated Solana RPC calls)
    try {
      _cachedGateways ??= await _arioSDK
          .getGateways()
          .timeout(_garListTimeout, onTimeout: () => <Gateway>[]);
      final gateways = _cachedGateways!;
      final primaryHost = primaryClient.api.gatewayUrl.host;

      var tried = 0;
      for (final gw in gateways) {
        if (tried >= _maxGarFallbacks) break;
        if (gw.settings.fqdn == primaryHost) continue;

        try {
          final client = _getOrCreateClient(gw.settings.fqdn);
          final response = await _tryGateway(client, txId);
          logger.i(
            'Fallback gateway ${gw.settings.fqdn} succeeded for tx $txId',
          );
          return response;
        } on _ErrorFromStatus catch (e) {
          if (!e.retryable) rethrow;
          if (e.statusCode != 404) all404 = false;
          logger.w(
            'Fallback gateway ${gw.settings.fqdn} failed for tx $txId: $e',
          );
          tried++;
          continue;
        } catch (e) {
          all404 = false;
          logger.w(
            'Fallback gateway ${gw.settings.fqdn} failed for tx $txId: $e',
          );
          tried++;
          continue;
        }
      }
    } catch (e) {
      all404 = false;
      logger.w('GAR list unavailable for fallback: $e');
    }

    // 3. Last resort: arweave.net
    logger.w('Trying last resort gateway $_lastResortGateway for tx $txId');
    try {
      final lastResortClient = _getOrCreateClient('arweave.net');
      final response = await _tryGateway(lastResortClient, txId);
      logger.i('Last resort gateway succeeded for tx $txId');
      return response;
    } on _ErrorFromStatus catch (e) {
      if (e.statusCode != 404) all404 = false;
    } catch (e) {
      all404 = false;
    }

    // All gateways failed
    if (all404) {
      throw TransactionNotFound(txId);
    }
    throw Exception('All gateways failed for tx $txId');
  }

  Future<Response> _tryGateway(Arweave client, String txId) async {
    Exception? lastError;

    for (var attempt = 0; attempt < _retryPerGateway; attempt++) {
      try {
        final response = await client.api
            .getSandboxedTx(txId)
            .timeout(_requestTimeout);

        if (response.statusCode >= 200 && response.statusCode <= 208) {
          return response;
        }

        if (!_isRetryableStatus(response.statusCode)) {
          throw _ErrorFromStatus(response.statusCode, txId, retryable: false);
        }

        throw _ErrorFromStatus(response.statusCode, txId);
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        if (attempt < _retryPerGateway - 1) {
          await Future.delayed(
            Duration(milliseconds: 500 * (attempt + 1)),
          );
        }
      }
    }

    throw lastError!;
  }

  bool _isRetryableStatus(int statusCode) =>
      statusCode == 404 ||
      statusCode == 429 ||
      (statusCode >= 500 && statusCode < 600);

  Arweave _getOrCreateClient(String fqdn) {
    return _clientCache.putIfAbsent(
      fqdn,
      () => Arweave(
        api: ArweaveApi(gatewayUrl: Uri.parse('https://$fqdn')),
      ),
    );
  }
}

class _ErrorFromStatus implements Exception {
  final int statusCode;
  final String txId;
  final bool retryable;

  _ErrorFromStatus(this.statusCode, this.txId, {this.retryable = true});

  @override
  String toString() => 'Gateway returned $statusCode for tx $txId';
}
