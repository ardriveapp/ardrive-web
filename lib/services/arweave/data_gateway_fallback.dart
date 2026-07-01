import 'dart:async';

import 'package:ardrive/download/download_exceptions.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/arweave.dart' as arweave_pkg;
import 'package:http/http.dart';

/// Provides data gateway fallback resilience using hedged (staggered) requests.
///
/// Instead of waiting for each gateway to fail before trying the next one,
/// fires additional requests in parallel after a short delay. The first
/// successful response wins and the rest are ignored.
///
/// Fallback order: primary → up to 2 GAR gateways → arweave.net
class DataGatewayFallback {
  final ArioSDK _arioSDK;
  final Map<String, Arweave> _clientCache = {};

  static const _maxGarFallbacks = 2;
  static const _garListTimeout = Duration(seconds: 5);
  static const _requestTimeout = Duration(seconds: 5);
  static const _downloadConnectTimeout = Duration(seconds: 10);
  static const _totalFetchTimeout = Duration(seconds: 15);
  static const _hedgeDelay = Duration(milliseconds: 1500);

  List<Gateway>? _cachedGateways;

  DataGatewayFallback({
    required ArioSDK arioSDK,
  }) : _arioSDK = arioSDK;

  /// Fetch transaction data with hedged gateway fallback.
  ///
  /// Fires primary immediately, then launches additional gateways every
  /// [_hedgeDelay] if no response yet. First 200 response wins.
  ///
  /// If ALL gateways return 404, throws [TransactionNotFound].
  Future<Response> fetchData(String txId, Arweave primaryClient) async {
    final clients = await _buildClientList(primaryClient);

    return _hedgedRequest<Response>(
      txId: txId,
      clients: clients,
      attempt: (client) => _tryGateway(client, txId),
      totalTimeout: _totalFetchTimeout,
    );
  }

  /// Download a file with hedged gateway fallback.
  ///
  /// Same staggered pattern as [fetchData] but initiates a streaming download.
  /// Only retries pre-stream failures (connection, 404, 500 before stream
  /// starts). Once bytes are streaming, failures propagate to the caller.
  ///
  /// Returns the download stream tuple from the first successful gateway.
  /// Throws [DownloadFileNotFoundException], [DownloadNetworkException], or
  /// [DownloadRateLimitException] on failure.
  Future<(Stream<List<int>>, void Function())> downloadWithFallback({
    required String txId,
    required Arweave primaryClient,
    Function(double progress, int speed)? onProgress,
    bool verifyDownload = false,
  }) async {
    final clients = await _buildClientList(primaryClient);

    try {
      return await _hedgedRequest<(Stream<List<int>>, void Function())>(
        txId: txId,
        clients: clients,
        attempt: (client) => arweave_pkg.download(
          txId: txId,
          arweave: client,
          onProgress: onProgress,
          verifyDownload: verifyDownload,
        ),
        totalTimeout: _downloadConnectTimeout,
      );
    } on TransactionNotFound {
      throw DownloadFileNotFoundException(txId);
    } catch (e) {
      if (e is DownloadFileNotFoundException ||
          e is DownloadRateLimitException) {
        rethrow;
      }
      throw DownloadNetworkException(txId, e.toString());
    }
  }

  /// Fetch manifest data with hedged gateway fallback.
  ///
  /// Replaces direct [ArDriveHTTP().getAsBytes()] calls that had no fallback.
  Future<Response> fetchManifestWithFallback(
      String txId, Arweave primaryClient) async {
    final clients = await _buildClientList(primaryClient);

    return _hedgedRequest<Response>(
      txId: txId,
      clients: clients,
      attempt: (client) => _tryManifestGateway(client, txId),
      totalTimeout: _totalFetchTimeout,
    );
  }

  /// Build the ordered list of clients: primary + GAR gateways + arweave.net.
  Future<List<Arweave>> _buildClientList(Arweave primaryClient) async {
    final clients = <Arweave>[primaryClient];
    final primaryHost = primaryClient.api.gatewayUrl.host;

    try {
      _cachedGateways ??= await _arioSDK
          .getGateways()
          .timeout(_garListTimeout, onTimeout: () => <Gateway>[]);

      var added = 0;
      for (final gw in _cachedGateways!) {
        if (added >= _maxGarFallbacks) break;
        if (gw.settings.fqdn == primaryHost) continue;
        clients.add(_getOrCreateClient(gw.settings.fqdn));
        added++;
      }
    } catch (e) {
      logger.w('GAR list unavailable for fallback: $e');
    }

    // Always include arweave.net as last resort
    if (primaryHost != 'arweave.net') {
      clients.add(_getOrCreateClient('arweave.net'));
    }

    return clients;
  }

  /// Execute a hedged request across multiple gateways.
  ///
  /// Fires the first client immediately, then launches additional clients
  /// every [_hedgeDelay] if no success yet. Returns the first successful
  /// result. If all fail, throws based on failure pattern (all-404 vs mixed).
  Future<T> _hedgedRequest<T>({
    required String txId,
    required List<Arweave> clients,
    required Future<T> Function(Arweave client) attempt,
    required Duration totalTimeout,
  }) async {
    if (clients.isEmpty) {
      throw Exception('No gateways available for tx $txId');
    }

    final completer = Completer<T>();
    var completedCount = 0;
    var all404 = true;
    var allRateLimited = true;
    Object? lastError;
    final futures = <Future>[];

    for (var i = 0; i < clients.length; i++) {
      if (completer.isCompleted) break;

      // Stagger: wait _hedgeDelay before launching each subsequent gateway
      if (i > 0) {
        await Future.any([
          Future.delayed(_hedgeDelay),
          completer.future.then((_) {}), // resolve immediately if already done
        ]);
        if (completer.isCompleted) break;
      }

      final client = clients[i];
      final gatewayName =
          i == 0 ? 'primary' : client.api.gatewayUrl.host;

      futures.add(
        attempt(client).then((result) {
          if (!completer.isCompleted) {
            if (i > 0) {
              logger.i('Hedged gateway $gatewayName won for tx $txId');
            }
            completer.complete(result);
          }
        }).catchError((Object e) {
          completedCount++;
          if (e is _ErrorFromStatus) {
            if (e.statusCode != 404) all404 = false;
            if (e.statusCode != 429) allRateLimited = false;
          } else {
            all404 = false;
            allRateLimited = false;
          }
          lastError = e;
          logger.w('Gateway $gatewayName failed for tx $txId: $e');

          // If all gateways have failed and none succeeded, complete with error
          if (completedCount == clients.length && !completer.isCompleted) {
            if (all404) {
              completer.completeError(TransactionNotFound(txId));
            } else if (allRateLimited) {
              completer.completeError(DownloadRateLimitException(txId));
            } else {
              completer.completeError(
                  lastError ?? Exception('All gateways failed for tx $txId'));
            }
          }
        }),
      );
    }

    return completer.future.timeout(totalTimeout, onTimeout: () {
      logger.w('Total fetch timeout exceeded for tx $txId');
      throw Exception('Total fetch timeout exceeded for tx $txId');
    });
  }

  Future<Response> _tryGateway(Arweave client, String txId) async {
    final response = await client.api
        .getSandboxedTx(txId)
        .timeout(_requestTimeout);

    if (response.statusCode >= 200 && response.statusCode <= 208) {
      return response;
    }

    throw _ErrorFromStatus(response.statusCode, txId);
  }

  Future<Response> _tryManifestGateway(Arweave client, String txId) async {
    final url = '${client.api.gatewayUrl.origin}/raw/$txId';
    final response =
        await ArDriveHTTP().get(url: url).timeout(_requestTimeout);

    final statusCode = response.statusCode ?? 0;
    if (statusCode >= 200 && statusCode <= 208) {
      return Response(response.data, statusCode);
    }

    throw _ErrorFromStatus(statusCode, txId);
  }

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

  _ErrorFromStatus(this.statusCode, this.txId);

  @override
  String toString() => 'Gateway returned $statusCode for tx $txId';
}
