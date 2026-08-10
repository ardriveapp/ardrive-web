import 'dart:async';

import 'package:ardrive/download/download_exceptions.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/arweave.dart' as arweave_pkg;
import 'package:http/http.dart';

/// Provides data gateway fallback resilience.
///
/// Two distinct read paths live here:
///
/// * **Sync reads** ([fetchDataForSync]) use the configured gateway only, with
///   a single retry, then skip the item. No GAR, therefore no Solana RPC.
///   Sync is high volume, so per-item attempt count dominates.
///
/// * **Everything else** — downloads, previews, thumbnails and shared links —
///   keeps the full waterfall (primary → up to 2 GAR gateways → arweave.net).
///   These are single user-initiated operations where a recipient with one
///   dead gateway must still get their file, so breadth beats latency.
///
/// File downloads additionally use hedged (staggered parallel) requests since
/// they are single user-initiated operations where latency matters.
class DataGatewayFallback {
  final ArioSDK _arioSDK;
  final Map<String, Arweave> _clientCache = {};

  static const _maxGarFallbacks = 2;
  static const _garListTimeout = Duration(seconds: 5);
  static const _requestTimeout = Duration(seconds: 5);
  static const _totalFetchTimeout = Duration(seconds: 25);
  static const _hedgeDelay = Duration(milliseconds: 1500);
  static const _downloadTimeout = Duration(seconds: 15);

  /// Attempts made against the configured gateway by [fetchDataForSync].
  static const syncMaxAttempts = 2;

  /// Delay before the single same-gateway retry in [fetchDataForSync].
  static const _syncRetryDelay = Duration(milliseconds: 300);

  /// Upper bound for one sync read. By construction the attempts already sum
  /// to ~10.3s; this only guards against an attempt that outlives its own
  /// timeout.
  static const _syncTotalFetchTimeout = Duration(seconds: 15);

  /// Cached gateway list — shared with other services (e.g.
  /// SnapshotValidationService) to avoid duplicate Solana RPC calls.
  List<Gateway>? cachedGateways;

  DataGatewayFallback({
    required ArioSDK arioSDK,
  }) : _arioSDK = arioSDK;

  /// Fetch transaction data with serial gateway fallback.
  ///
  /// Tries: primary → up to 2 GAR gateways → arweave.net
  /// Used for metadata fetches during sync (called hundreds of times).
  ///
  /// If ALL gateways return 404, throws [TransactionNotFound].
  Future<Response> fetchData(String txId, Arweave primaryClient) async {
    return _serialFetch(txId, primaryClient)
        .timeout(_totalFetchTimeout, onTimeout: () {
      logger.w('Total fetch timeout exceeded for tx $txId');
      throw Exception('Total fetch timeout exceeded for tx $txId');
    });
  }

  /// Fetch transaction data for **sync** metadata reads.
  ///
  /// Reads the configured gateway only: one attempt, one retry on a transient
  /// failure, then give up so the caller can skip the item and carry on. Never
  /// consults the GAR, so no Solana RPC is issued on the sync path.
  ///
  /// Sync issues hundreds of these per run, where per-item attempt count
  /// dominates: the [fetchData] waterfall costs up to 4 serial attempts at 5s
  /// each, so a slow or flaky primary turns into minutes of serial timeouts.
  /// Worst case here is [syncMaxAttempts] attempts / ~10.3s.
  ///
  /// A 404 is not retried — the same host will not change its mind.
  ///
  /// Callers must treat a failure as "skip this item", and must record the tx
  /// id so it is not lost. See the note on `ArweaveService._getEntityData` and
  /// `docs/SYNC_SKIPPED_ENTITY_PERSISTENCE.md`.
  ///
  /// If every attempt 404s, throws [TransactionNotFound].
  Future<Response> fetchDataForSync(String txId, Arweave primaryClient) async {
    return _syncFetch(txId, primaryClient)
        .timeout(_syncTotalFetchTimeout, onTimeout: () {
      logger.w('Total sync fetch timeout exceeded for tx $txId');
      throw Exception('Total sync fetch timeout exceeded for tx $txId');
    });
  }

  Future<Response> _syncFetch(String txId, Arweave primaryClient) async {
    final gatewayName = primaryClient.api.gatewayUrl.host;

    for (var attempt = 1; attempt <= syncMaxAttempts; attempt++) {
      try {
        return await _tryGateway(primaryClient, txId);
      } on _ErrorFromStatus catch (e) {
        if (e.statusCode == 404) {
          // Retrying the same host cannot turn a 404 into a 200.
          logger.w('Gateway $gatewayName returned 404 for sync tx $txId');
          throw TransactionNotFound(txId);
        }
        logger.w('Gateway $gatewayName failed for sync tx $txId '
            '(attempt $attempt/$syncMaxAttempts): $e');
      } catch (e) {
        logger.w('Gateway $gatewayName failed for sync tx $txId '
            '(attempt $attempt/$syncMaxAttempts): $e');
      }

      if (attempt < syncMaxAttempts) {
        await Future.delayed(_syncRetryDelay);
      }
    }

    throw Exception(
      'Gateway $gatewayName failed for sync tx $txId '
      'after $syncMaxAttempts attempts',
    );
  }

  Future<Response> _serialFetch(String txId, Arweave primaryClient) async {
    final clients = await _buildClientList(primaryClient);
    var all404 = true;

    for (final client in clients) {
      final gatewayName = client.api.gatewayUrl.host;
      try {
        final response = await _tryGateway(client, txId);
        if (client != primaryClient) {
          logger.i('Fallback gateway $gatewayName succeeded for tx $txId');
        }
        return response;
      } on _ErrorFromStatus catch (e) {
        if (e.statusCode != 404) all404 = false;
        logger.w('Gateway $gatewayName failed for tx $txId: $e');
      } catch (e) {
        all404 = false;
        logger.w('Gateway $gatewayName failed for tx $txId: $e');
      }
    }

    if (all404) {
      throw TransactionNotFound(txId);
    }
    throw Exception('All gateways failed for tx $txId');
  }

  /// Download a file with hedged (staggered parallel) gateway fallback.
  ///
  /// Fires primary immediately, then launches additional gateways every
  /// [_hedgeDelay] if no response yet. First successful response wins.
  /// Used for single user-initiated downloads where latency matters.
  ///
  /// Only retries pre-stream failures (connection, 404, 500 before stream
  /// starts). Once bytes are streaming, failures propagate to the caller.
  ///
  /// Throws [DownloadFileNotFoundException], [DownloadNetworkException], or
  /// [DownloadRateLimitException] on failure.
  Future<(Stream<List<int>>, void Function())> downloadWithFallback({
    required String txId,
    required Arweave primaryClient,
    Function(double progress, int speed)? onProgress,
    bool verifyDownload = false,
  }) async {
    final clients = await _buildClientList(primaryClient);
    var all404 = true;

    // Hedged: fire primary, then stagger fallbacks
    final completer = Completer<(Stream<List<int>>, void Function())>();
    var failedCount = 0;

    for (var i = 0; i < clients.length; i++) {
      if (completer.isCompleted) break;

      // Stagger: wait before launching each subsequent gateway
      if (i > 0) {
        await Future.any([
          Future.delayed(_hedgeDelay),
          completer.future.then((_) {}),
        ]);
        if (completer.isCompleted) break;
      }

      final client = clients[i];
      final gatewayName = i == 0 ? 'primary' : client.api.gatewayUrl.host;

      // Fire and don't await — let the completer collect the winner
      unawaited(
        arweave_pkg
            .download(
          txId: txId,
          arweave: client,
          onProgress: onProgress,
          verifyDownload: verifyDownload,
        )
            .then((result) {
          if (!completer.isCompleted) {
            if (i > 0) {
              logger.i('Hedged gateway $gatewayName won download for tx $txId');
            }
            completer.complete(result);
          }
        }).catchError((Object e) {
          failedCount++;
          if (e is! _ErrorFromStatus || e.statusCode != 404) {
            all404 = false;
          }
          logger.w('Download gateway $gatewayName failed for tx $txId: $e');

          if (failedCount == clients.length && !completer.isCompleted) {
            if (all404) {
              completer.completeError(DownloadFileNotFoundException(txId));
            } else {
              completer.completeError(
                  DownloadNetworkException(txId, e.toString()));
            }
          }
        }),
      );
    }

    return completer.future.timeout(_downloadTimeout, onTimeout: () {
      throw DownloadNetworkException(txId, 'Download connection timed out');
    });
  }

  /// Fetch manifest data with serial gateway fallback.
  Future<Response> fetchManifestWithFallback(
      String txId, Arweave primaryClient) async {
    final clients = await _buildClientList(primaryClient);
    var all404 = true;

    for (final client in clients) {
      final gatewayName = client.api.gatewayUrl.host;
      try {
        final response = await _tryManifestGateway(client, txId);
        if (client != primaryClient) {
          logger.i(
              'Fallback gateway $gatewayName succeeded for manifest $txId');
        }
        return response;
      } on _ErrorFromStatus catch (e) {
        if (e.statusCode != 404) all404 = false;
        logger.w('Gateway $gatewayName failed for manifest $txId: $e');
      } catch (e) {
        all404 = false;
        logger.w('Gateway $gatewayName failed for manifest $txId: $e');
      }
    }

    if (all404) {
      throw TransactionNotFound(txId);
    }
    throw Exception('All gateways failed for manifest $txId');
  }

  /// Build the ordered list of clients: primary + GAR gateways + arweave.net.
  Future<List<Arweave>> _buildClientList(Arweave primaryClient) async {
    final clients = <Arweave>[primaryClient];
    final primaryHost = primaryClient.api.gatewayUrl.host;

    try {
      if (cachedGateways == null) {
        try {
          cachedGateways = await _arioSDK
              .getGateways()
              .timeout(_garListTimeout, onTimeout: () => <Gateway>[]);
        } catch (e) {
          // Solana RPC failed — cache empty list so we don't retry every call
          logger.w('GAR list unavailable for fallback, will not retry: $e');
          cachedGateways = [];
        }
      }

      var added = 0;
      for (final gw in cachedGateways!) {
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
