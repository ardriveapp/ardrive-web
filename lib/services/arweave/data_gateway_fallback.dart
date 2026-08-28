import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/components/sandboxed_transaction_view/arweave_sandbox_url.dart';
import 'package:ardrive/download/download_exceptions.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/arweave.dart' as arweave_pkg;
import 'package:flutter/foundation.dart';
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

  /// How long one gateway read waits before being abandoned.
  ///
  /// Ten seconds, not five. Sync reads run through [ArweaveService.runPooled],
  /// a worker pool with a shared cursor, so a read that hangs occupies one of
  /// its `maxConcurrentDataFetches` slots while the other workers keep pulling
  /// new items. A longer wait therefore costs throughput on one slot rather
  /// than stalling the sync, which is what makes it affordable to be patient
  /// enough for a gateway that is a beat behind rather than broken.
  static const _requestTimeout = Duration(seconds: 10);

  /// Per-read budget for a body measured in tens of megabytes.
  ///
  /// [_requestTimeout] is sized for the metadata reads that dominate sync -
  /// a few hundred bytes each, hundreds of them. A snapshot is the same call
  /// with four orders of magnitude more body: this drive's newest is 43.9 MiB,
  /// and a warm gateway serves it in ~8s at ~5.7 MB/s. Under the metadata
  /// budget it could never finish, on any connection slower than ~9 MB/s, no
  /// matter how many times it was retried.
  ///
  /// Sixty seconds covers that body down to about 0.75 MB/s. Being generous is
  /// cheap here in a way it is not for metadata: this is one request per
  /// snapshot rather than one per entity, its availability has already been
  /// established by a HEAD before the download starts
  /// (`SnapshotValidationService`), and the alternative to waiting is
  /// re-walking the snapshot's whole block range over GraphQL, which costs
  /// minutes.
  static const largeBodyRequestTimeout = Duration(seconds: 60);

  /// Total budget for a large-body read, covering both attempts.
  static const largeBodyTotalTimeout = Duration(seconds: 130);

  /// Backstop for the whole [fetchData] waterfall.
  ///
  /// Generous, and not a deadline anyone is meant to reach. Each attempt there
  /// is bounded by silence rather than duration, so a hung gateway is dropped
  /// in [_requestTimeout] and four of them cost well under a minute. What this
  /// still catches is a gateway dribbling bytes indefinitely - fast enough
  /// never to go quiet, too slow to ever finish.
  ///
  /// It was twenty five seconds, which was a deadline: a fifty megabyte
  /// preview needed 2 MB/s to fit inside it, so the cap ended reads that were
  /// working.
  static const _totalFetchTimeout = Duration(minutes: 3);
  static const _hedgeDelay = Duration(milliseconds: 1500);
  static const _downloadTimeout = Duration(seconds: 15);

  /// Attempts made against the configured gateway by [fetchDataForSync].
  static const syncMaxAttempts = 2;

  /// Attempts against the configured gateway inside the [fetchData] waterfall,
  /// spent only when it answers 404.
  static const _primaryAttemptsOn404 = 2;

  /// Delay before that retry.
  static const _primaryRetryDelay = Duration(milliseconds: 300);

  /// Delay before the single same-gateway retry in [fetchDataForSync].
  static const _syncRetryDelay = Duration(milliseconds: 300);

  /// Upper bound for one sync read.
  ///
  /// This has to clear what the attempts themselves can spend, or it silently
  /// becomes the real limit: [syncMaxAttempts] attempts at [_requestTimeout]
  /// plus one [_syncRetryDelay] is 20.3s, so a 15s cap - correct when an
  /// attempt was 5s - would cut the second attempt off at 4.7s and make the
  /// retry weaker than the try it was retrying.
  ///
  /// It is a backstop against an attempt that outlives its own timeout, not a
  /// budget in its own right, so it sits just above that sum.
  static const _syncTotalFetchTimeout = Duration(seconds: 22);

  /// The sync read budgets, together, so a test can assert the relationship
  /// between them rather than restate their values - restating them is what
  /// drifted when [_requestTimeout] changed and the cap did not.
  @visibleForTesting
  static const syncBudgets = (
    request: _requestTimeout,
    retryDelay: _syncRetryDelay,
    total: _syncTotalFetchTimeout,
  );

  /// Cached gateway list — shared with other services (e.g.
  /// SnapshotValidationService) to avoid duplicate Solana RPC calls.
  List<Gateway>? cachedGateways;

  /// Injectable so a test can prove that [fetchDataForSync]'s `largeBody`
  /// routes to a different budget without spending either of them.
  final Duration _syncRequestTimeout;
  final Duration _syncLargeBodyRequestTimeout;

  /// Injectable so a test can make a body outlive its own budget, which is the
  /// only way to tell a stall timeout from a deadline.
  final Duration _dataRequestTimeout;

  /// Injectable for the same reason: the backstop is three minutes, and a test
  /// has to be able to reach it to prove the connection is hung up.
  final Duration _dataTotalTimeout;

  DataGatewayFallback({
    required ArioSDK arioSDK,
    Client Function()? clientFactory,
    @visibleForTesting Duration? syncRequestTimeout,
    @visibleForTesting Duration? syncLargeBodyRequestTimeout,
    @visibleForTesting Duration? dataRequestTimeout,
    @visibleForTesting Duration? dataTotalTimeout,
  })  : _arioSDK = arioSDK,
        _clientFactory = clientFactory ?? Client.new,
        _dataRequestTimeout = dataRequestTimeout ?? _requestTimeout,
        _dataTotalTimeout = dataTotalTimeout ?? _totalFetchTimeout,
        _syncRequestTimeout = syncRequestTimeout ?? _requestTimeout,
        _syncLargeBodyRequestTimeout =
            syncLargeBodyRequestTimeout ?? largeBodyRequestTimeout;

  /// Fetch transaction data with serial gateway fallback.
  ///
  /// Tries: primary → up to 2 GAR gateways → arweave.net
  /// Used for metadata fetches during sync (called hundreds of times).
  ///
  /// If ALL gateways return 404, throws [TransactionNotFound].
  Future<Response> fetchData(String txId, Arweave primaryClient) async {
    // One client for the whole waterfall, so the backstop below has something
    // to hang up with. `Future.timeout` does not cancel what it times out: the
    // read would otherwise carry on buffering - up to the 100 MiB preview cap -
    // and holding its connection long after the caller was told it had failed.
    // Closing the client aborts the request in flight (`BrowserClient.close`
    // fires its `AbortController`).
    final httpClient = _clientFactory();

    try {
      return await _serialFetch(txId, primaryClient, httpClient: httpClient)
          .timeout(_dataTotalTimeout, onTimeout: () {
        logger.w('Total fetch timeout exceeded for tx $txId');
        httpClient.close();

        throw Exception('Total fetch timeout exceeded for tx $txId');
      });
    } finally {
      httpClient.close();
    }
  }

  /// Fetch transaction data for **sync** metadata reads.
  ///
  /// Reads the configured gateway only: one attempt, one retry on a transient
  /// failure, then give up so the caller can skip the item and carry on. Never
  /// consults the GAR, so no Solana RPC is issued on the sync path.
  ///
  /// Sync issues hundreds of these per run, where per-item attempt count
  /// dominates: the [fetchData] waterfall costs up to 4 serial attempts, so a
  /// slow or flaky primary turns into minutes of serial timeouts. Worst case
  /// here is [syncMaxAttempts] attempts against one host.
  ///
  /// A 404 is retried like any other failure: a gateway that has not
  /// finished indexing a transaction answers 404 for it and 200 a moment
  /// later. [TransactionNotFound] is reported only when *every* attempt
  /// returned 404 — a 500 followed by a 404 is an unwell gateway, not an
  /// absent transaction.
  ///
  /// Callers must treat a failure as "skip this item", and must record the tx
  /// id so it is not lost. See the note on `ArweaveService._getEntityData` and
  /// `docs/SYNC_SKIPPED_ENTITY_PERSISTENCE.md`.
  ///
  /// If every attempt 404s, throws [TransactionNotFound].
  ///
  /// [largeBody] switches to [largeBodyRequestTimeout], for reads whose body
  /// is measured in megabytes rather than bytes - snapshots. The default
  /// budget is sized for metadata and cannot finish one.
  Future<Response> fetchDataForSync(
    String txId,
    Arweave primaryClient, {
    bool largeBody = false,
  }) async {
    return _syncFetch(txId, primaryClient, largeBody: largeBody)
        .timeout(largeBody ? largeBodyTotalTimeout : _syncTotalFetchTimeout,
            onTimeout: () {
      logger.w('Total sync fetch timeout exceeded for tx $txId');
      throw Exception('Total sync fetch timeout exceeded for tx $txId');
    });
  }

  Future<Response> _syncFetch(
    String txId,
    Arweave primaryClient, {
    bool largeBody = false,
  }) async {
    final gatewayName = primaryClient.api.gatewayUrl.host;

    var allAttempts404 = true;

    for (var attempt = 1; attempt <= syncMaxAttempts; attempt++) {
      try {
        return await _tryGateway(
          primaryClient,
          txId,
          requestTimeout:
              largeBody ? _syncLargeBodyRequestTimeout : _syncRequestTimeout,
        );
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
        if (e.statusCode != 404) {
          allAttempts404 = false;
        }

        // `TransactionNotFound` is a claim that the transaction is absent, so
        // only every attempt agreeing earns it. A 500 followed by a 404 says
        // the gateway was unwell, not that the data is gone, and reporting it
        // as not-found would state more than we know.
        if (e.statusCode == 404 &&
            attempt == syncMaxAttempts &&
            allAttempts404) {
          logger.w('Gateway $gatewayName returned 404 for sync tx $txId '
              'on every attempt');
          throw TransactionNotFound(txId);
        }
        logger.w('Gateway $gatewayName failed for sync tx $txId '
            '(attempt $attempt/$syncMaxAttempts): $e');
      } catch (e) {
        // A timeout or a socket error is not a 404 either.
        allAttempts404 = false;
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

  Future<Response> _serialFetch(
    String txId,
    Arweave primaryClient, {
    required Client httpClient,
  }) async {
    final clients = await _buildClientList(primaryClient);
    var all404 = true;

    for (final client in clients) {
      final gatewayName = client.api.gatewayUrl.host;
      final isPrimary = client == primaryClient;

      // The configured gateway gets one extra attempt, and only on a 404.
      // [_syncFetch] already spends one for the same reason - a gateway that
      // has not finished indexing a transaction answers 404 for it and 200 a
      // moment later - and the reasoning holds at least as well here, because
      // walking away from the primary is worst for exactly the data most
      // likely to be a beat behind. Something just uploaded through Turbo can
      // be on the configured gateway and not yet anywhere else, so falling
      // through on its first 404 reaches gateways that are further behind it,
      // not ahead of it.
      //
      // Deliberately not extended to timeouts or socket errors: those have
      // already spent their [_requestTimeout] and say the gateway is unwell
      // rather than a beat behind, so the next gateway is the better bet and
      // the total budget stays intact.
      final attempts = isPrimary ? _primaryAttemptsOn404 : 1;

      for (var attempt = 1; attempt <= attempts; attempt++) {
        var retryable = false;

        try {
          final response = await _tryGatewayStreamed(client, txId, httpClient);
          if (!isPrimary) {
            logger.i('Fallback gateway $gatewayName succeeded for tx $txId');
          }
          return response;
        } on _ErrorFromStatus catch (e) {
          if (e.statusCode != 404) all404 = false;
          retryable = e.statusCode == 404;
          logger.w('Gateway $gatewayName failed for tx $txId: $e');
        } catch (e) {
          all404 = false;
          logger.w('Gateway $gatewayName failed for tx $txId: $e');
        }

        if (!retryable) break;

        if (attempt < attempts) {
          await Future.delayed(_primaryRetryDelay);
        }
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
              completer
                  .completeError(DownloadNetworkException(txId, e.toString()));
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
          logger
              .i('Fallback gateway $gatewayName succeeded for manifest $txId');
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

  /// A gateway read whose budget measures **silence**, not duration.
  ///
  /// [_tryGateway] buffers the whole body behind one `Future`, and a `Future`
  /// timeout is a deadline on the transfer - it cannot tell a gateway that has
  /// stopped answering from fifty megabytes arriving perfectly well. Previews
  /// are capped at 100 MiB, so under that deadline a large file could not be
  /// read from any gateway: each was abandoned mid-body on any connection
  /// slower than the file divided by the budget, and the user saw
  /// "unpreviewable" for a file that was arriving fine.
  ///
  /// Reading the body as a stream makes the timeout fire only when no chunk
  /// has arrived for that long. A slow body finishes; a dead gateway is still
  /// dropped just as quickly. `BrowserClient` reads through a `ReadableStream`,
  /// so this is chunk-wise on the web too, not only on the VM.
  ///
  /// Sync deliberately keeps [_tryGateway]: its reads are a few hundred bytes
  /// each and there are hundreds of them, so a wall clock is the right shape
  /// there and one less moving part.
  Future<Response> _tryGatewayStreamed(
    Arweave client,
    String txId,
    Client httpClient, {
    Duration? requestTimeout,
  }) async {
    final budget = requestTimeout ?? _dataRequestTimeout;

    {
      final request = Request(
        'GET',
        Uri.parse(
          arweaveSandboxUrl(txId: txId, gatewayUrl: client.api.gatewayUrl) ??
              '${client.api.gatewayUrl.origin}/$txId',
        ),
      );

      final response = await httpClient.send(request).timeout(budget);

      if (response.statusCode < 200 || response.statusCode > 208) {
        throw _ErrorFromStatus(response.statusCode, txId);
      }

      final chunks = <List<int>>[];
      var length = 0;

      await for (final chunk in response.stream.timeout(budget)) {
        chunks.add(chunk);
        length += chunk.length;
      }

      final body = Uint8List(length);
      var offset = 0;

      for (final chunk in chunks) {
        body.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }

      return Response.bytes(
        body,
        response.statusCode,
        headers: response.headers,
        reasonPhrase: response.reasonPhrase,
      );
    }
  }

  Future<Response> _tryGateway(
    Arweave client,
    String txId, {
    Duration? requestTimeout,
  }) async {
    final response = await client.api
        .getSandboxedTx(txId)
        .timeout(requestTimeout ?? _requestTimeout);

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
