import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/download/download_exceptions.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/utils/logger.dart';
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

  /// Injectable so the methods here that talk to a gateway themselves rather
  /// than through an [Arweave] client - [fetchDataAtMost] and the manifest
  /// fetch - can be tested without a network.
  final Client Function() _clientFactory;

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
    Client Function()? clientFactory,
  })  : _arioSDK = arioSDK,
        _clientFactory = clientFactory ?? Client.new;

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
        // A 404 is NOT treated as final here, and the reasoning that said it
        // was is wrong for this case. A gateway that has not finished indexing
        // a transaction answers 404 for it, and answers 200 a moment later -
        // observed in the wild on a drive signature that 404ed once and
        // resolved on the retry. Spending the second attempt is cheap; losing
        // a drive because its gateway was a beat behind is not.
        //
        // The last attempt still reports it as not found, so a genuinely
        // absent transaction keeps its typed error.
        if (e.statusCode == 404 && attempt == syncMaxAttempts) {
          logger.w('Gateway $gatewayName returned 404 for sync tx $txId '
              'on every attempt');
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

  /// Fetch at most [maxBytes] of a transaction's data, through the same serial
  /// waterfall as [fetchData].
  ///
  /// Returns `null` when the transaction turns out to be bigger than that, and
  /// abandons the response the moment it says so — either because the gateway
  /// declared a larger body or because it sent one byte too many. An oversized
  /// transaction therefore costs [maxBytes], not its own size.
  ///
  /// This exists because [fetchData] cannot answer the question: it hands back
  /// a fully buffered [Response], so a caller that only wants small data has
  /// already paid for all of it by the time it can measure anything. That is
  /// fine for data whose size the caller already knows, and wrong for data
  /// whose id came out of somebody else's link (`thn` on a share link — see
  /// `SharedFileThumbnailLoader`).
  ///
  /// How the cap is asked for and enforced is [_fetchStreamed]'s.
  Future<Uint8List?> fetchDataAtMost(
    String txId,
    Arweave primaryClient, {
    required int maxBytes,
  }) =>
      _fetchStreamed(txId, primaryClient, maxBytes: maxBytes);

  /// A file's whole data, through the same serial waterfall.
  ///
  /// [fetchData] is the wrong tool for a file. It caps each gateway attempt at
  /// [_requestTimeout] and the whole waterfall at [_totalFetchTimeout], and
  /// those cover the *body* as well as the headers - correct for a metadata
  /// transaction, and hopeless for the hundreds of megabytes a multi-file
  /// download asks for. This applies the two timeouts a file transfer wants
  /// instead: one to reach the headers, and one to the *gap* between chunks, so
  /// a large but healthy transfer is never mistaken for a dead gateway.
  ///
  /// Buffered whole, like the single-gateway fetch it replaces. Callers that
  /// want the bytes as they arrive want [downloadWithFallback].
  Future<Uint8List> fetchFileData(String txId, Arweave primaryClient) async {
    // Only ever null when a cap was given and the transaction passed it.
    return (await _fetchStreamed(txId, primaryClient))!;
  }

  /// The waterfall both streamed fetches share.
  ///
  /// With a [maxBytes] cap, requested as `Range: bytes=0-{maxBytes}` and
  /// answered with `null` the moment the transaction turns out to be bigger -
  /// either because the gateway declared a larger body or because it sent one
  /// byte too many. A gateway that honours the header sends no more than the
  /// cap; a gateway that ignores it (arweave.net does — see
  /// `docs/FILE_SHARING_REDESIGN_PLAN.md` §3.2) is cut off by the running count
  /// instead. Nothing here branches on having sent the header.
  ///
  /// Without one, the body is read to its end and `null` is never returned.
  Future<Uint8List?> _fetchStreamed(
    String txId,
    Arweave primaryClient, {
    int? maxBytes,
  }) async {
    final clients = await _buildClientList(primaryClient);
    Object? lastError;

    for (final client in clients) {
      final gatewayName = client.api.gatewayUrl.host;
      final httpClient = _clientFactory();

      try {
        final request = Request(
          'GET',
          Uri.parse('${client.api.gatewayUrl.origin}/$txId'),
        );

        if (maxBytes != null) {
          request.headers['Range'] = 'bytes=0-$maxBytes';
        }

        final response =
            await httpClient.send(request).timeout(_requestTimeout);

        if (response.statusCode < 200 || response.statusCode > 208) {
          lastError = _ErrorFromStatus(response.statusCode, txId);
          logger.w('Gateway $gatewayName failed for tx $txId: $lastError');
          continue;
        }

        // The cheapest way to find out, and the one that costs no body at all:
        // a `206` declares the length of the range it is about to send, and a
        // `200` that ignored the header declares the whole transaction.
        final declared = response.contentLength;

        if (maxBytes != null && declared != null && declared > maxBytes) {
          logger.d(
            'Not fetching tx $txId: it declares $declared bytes, over the '
            '$maxBytes byte cap',
          );

          return null;
        }

        final bytes = await _readAtMost(
          response.stream.timeout(_requestTimeout),
          maxBytes,
        );

        if (bytes == null) {
          logger.d(
            'Abandoned tx $txId part way through: it sent more than the '
            '$maxBytes byte cap',
          );
        }

        // Either the data, or a transaction that is too big to be what the
        // caller asked for. Another gateway would answer the same, since it is
        // the same transaction.
        return bytes;
      } catch (e) {
        lastError = e;
        logger.w('Gateway $gatewayName failed for tx $txId: $e');
      } finally {
        // Closes the connection whether it was read to the end, cut off at the
        // cap, or never read at all.
        httpClient.close();
      }
    }

    throw Exception('All gateways failed for tx $txId: $lastError');
  }

  /// [body] collected, or `null` as soon as it passes [maxBytes].
  ///
  /// Leaving the loop early cancels the subscription, so the bytes after the
  /// cap are never pulled. A `null` [maxBytes] reads the body to its end.
  static Future<Uint8List?> _readAtMost(
    Stream<List<int>> body,
    int? maxBytes,
  ) async {
    final builder = BytesBuilder(copy: false);

    await for (final chunk in body) {
      builder.add(chunk);

      if (maxBytes != null && builder.length > maxBytes) {
        return null;
      }
    }

    return builder.takeBytes();
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

  /// A manifest's own bytes, from the gateway's `/raw/` endpoint.
  ///
  /// Read as bytes, and never as text that is then re-encoded. A manifest is
  /// UTF-8 JSON whose `paths` map is keyed by file names, so any drive with an
  /// emoji or a CJK character in a file name has a manifest that is not
  /// Latin-1. `Response(String, int)` encodes with latin1 - that is
  /// `package:http`'s default when no `content-type` charset says otherwise -
  /// and throws on the first character it cannot represent. That throw used to
  /// land in the waterfall's `catch`, be counted as this gateway failing, and
  /// reach the user as "all gateways failed" once every gateway had returned
  /// the same perfectly good manifest.
  Future<Response> _tryManifestGateway(Arweave client, String txId) async {
    final httpClient = _clientFactory();

    try {
      final response = await httpClient
          .get(Uri.parse('${client.api.gatewayUrl.origin}/raw/$txId'))
          .timeout(_requestTimeout);

      if (response.statusCode >= 200 && response.statusCode <= 208) {
        return response;
      }

      throw _ErrorFromStatus(response.statusCode, txId);
    } finally {
      // The body is fully buffered by the time `get` returns, so there is
      // nothing left to read off this connection either way.
      httpClient.close();
    }
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
