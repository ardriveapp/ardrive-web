import 'dart:async';

import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/snapshots/snapshot_item.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class SnapshotValidationService {
  final ConfigService _configService;

  /// How long one probe waits before being abandoned.
  ///
  /// Ten seconds, not five. Measured across three live snapshots of one drive
  /// (Aug 2026), turbo-gateway answered 12 probes in 0.68-6.08s with a single
  /// hang - and two of those, at 5.85s and 6.08s, were healthy answers that a
  /// 5s cutoff threw away. Nothing about that band is a failure; it is a
  /// gateway that had to fetch before it could answer.
  ///
  /// It is not raised further than that. A hung read here does not come back
  /// in 20s or 30s - it did not come back within 45 - so a bigger number buys
  /// no successes and delays every rejection. Ten clears the observed healthy
  /// band with margin and stops there; the retries below cover the rest.
  static const _defaultHeadTimeout = Duration(seconds: 10);

  static const _maxConcurrentValidations = 3;

  /// Injectable so a timeout can be exercised in a test without spending one.
  final Duration _headTimeout;

  /// Delay *before* each retry, indexed by the attempt just finished.
  ///
  /// Its length sets the retry budget. Losing a metadata read costs one
  /// entity; losing a snapshot costs its entire block range, which sync then
  /// re-queries over GraphQL - for an old drive that is thousands of
  /// transactions and the ghost folders that come with them. The expensive
  /// failure should not be the one given the fewest chances, so this budget is
  /// deliberately larger than a metadata read's.
  ///
  /// Measured against turbo-gateway.com on a live snapshot (Aug 2026), the
  /// response time is bimodal rather than merely slow: 0.69s, 0.96s and 22.9s
  /// on three tries, and no response at all within 45s on the other two. The
  /// shape is consistent with a cold read fetching the data before it can
  /// answer, and answering from cache once it has.
  ///
  /// That shape decides the strategy. A longer timeout is the wrong lever - it
  /// pays the tail on every failure and still cannot outwait an unbounded one.
  /// Short probes are right, but only if they are spread out: retrying 300ms
  /// after a timeout just lands inside the same cold read and hangs again,
  /// spending the whole budget to be told the same thing. Against the 10s
  /// [_defaultHeadTimeout], these delays start the four probes at roughly
  /// t=0s, 11s, 24s and 40s, so the later ones get a chance to land after a
  /// cold read has finished and the answer is cached.
  ///
  /// Worst case is ~50s for a snapshot that never answers once, and the common
  /// case is one probe of well under a second. That is the right trade against
  /// re-walking its block range, which costs minutes.
  static const _defaultRetryDelays = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 3),
    Duration(seconds: 6),
  ];

  final List<Duration> _retryDelays;

  /// One probe, plus one more after each delay.
  int get _maxAttempts => _retryDelays.length + 1;

  /// Builds the client for a single probe.
  ///
  /// One client per attempt, rather than one for the service, because
  /// `Future.timeout` abandons a response without cancelling the request that
  /// would have produced it. Closing the client does cancel it, and a probe
  /// that has timed out is exactly a request nothing is waiting for any more.
  ///
  /// Left pending they accumulate: four attempts across three concurrent
  /// validations is up to twelve requests outstanding against a gateway
  /// already too slow to answer one. On the web that is the worse half of the
  /// problem - browsers cap concurrent connections per host at around six, so
  /// abandoned probes would crowd out the reads sync makes to the same
  /// gateway immediately afterwards.
  ///
  /// Injectable so the retry behaviour can be tested without a network.
  final http.Client Function() _clientFactory;

  SnapshotValidationService({
    required ConfigService configService,
    @visibleForTesting http.Client Function()? clientFactory,
    @visibleForTesting List<Duration>? retryDelays,
    @visibleForTesting Duration? headTimeout,
  })  : _configService = configService,
        _clientFactory = clientFactory ?? http.Client.new,
        _retryDelays = retryDelays ?? _defaultRetryDelays,
        _headTimeout = headTimeout ?? _defaultHeadTimeout;

  Future<List<SnapshotItem>> validateSnapshotItems(
    List<SnapshotItem> snapshotItems,
  ) async {
    final List<SnapshotItem> snapshotsVerified = [];
    final primaryUrl = _configService.config.arweaveGatewayForDataRequest.url;

    // Limit concurrent HEAD requests to avoid gateway rate-limiting (402)
    final remaining = List<SnapshotItem>.from(snapshotItems);
    while (remaining.isNotEmpty) {
      final batch = remaining.take(_maxConcurrentValidations).toList();
      remaining.removeRange(0, batch.length);

      await Future.wait(batch.map((snapshotItem) async {
        try {
          final isValid =
              await _validateSnapshot(snapshotItem.txId, primaryUrl);

          if (isValid) {
            logger.d('Snapshot ${snapshotItem.txId} is valid');
            snapshotsVerified.add(snapshotItem);
          } else {
            logger.w('Snapshot ${snapshotItem.txId} failed validation');
          }
        } catch (e, stackTrace) {
          logger.e(
            'Error while validating snapshot ${snapshotItem.txId}',
            e,
            stackTrace,
          );
        }
      }));
    }

    return snapshotsVerified;
  }

  /// Validates a snapshot is available on the configured gateway.
  ///
  /// Up to [_maxAttempts] HEADs against the configured gateway, spaced by
  /// [_retryDelays]; anything other than 200/302 on every one of them rejects
  /// the snapshot, and sync falls back to GQL for that range - correct, but
  /// expensive enough that it is worth several probes to avoid.
  ///
  /// There is deliberately no GAR fallback here, and no second host of any
  /// kind. The GAR cost a Solana RPC via `ArioSDK.getGateways()`, which the
  /// sync path must not issue; reaching past the configured gateway to a
  /// hardcoded one is a product decision that has been made the other way.
  /// Spending more attempts on the configured gateway is the resilience that
  /// remains available, which is why the budget here is what it is.
  Future<bool> _validateSnapshot(String txId, String primaryUrl) async {
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      final client = _clientFactory();

      try {
        final response =
            await client.head(Uri.parse('$primaryUrl/$txId')).timeout(
                  _headTimeout,
                );

        if (response.statusCode == 200 || response.statusCode == 302) {
          return true;
        }

        // A refusal the same host will repeat. Retrying spends time to be
        // told the same thing.
        if (_isNonRetryable(response.statusCode)) {
          logger.w(
            'Snapshot $txId rejected: '
            'non-retryable status ${response.statusCode}',
          );
          return false;
        }

        logger.w(
          'Snapshot $txId: HEAD returned ${response.statusCode} '
          '(attempt $attempt/$_maxAttempts)',
        );
      } on TimeoutException {
        logger.w('Snapshot $txId: HEAD timed out '
            '(attempt $attempt/$_maxAttempts)');
      } catch (e) {
        logger.w('Snapshot $txId: HEAD error '
            '(attempt $attempt/$_maxAttempts): $e');
      } finally {
        // Cancels the request if this attempt timed out, and is harmless once
        // a response has arrived - a HEAD has no body left to read.
        client.close();
      }

      if (attempt < _maxAttempts) {
        await Future.delayed(_retryDelays[attempt - 1]);
      }
    }

    logger.w('Snapshot $txId rejected after $_maxAttempts attempts, '
        'falling back to GQL for its range');

    return false;
  }

  /// Status codes that should not be retried or fallback-rotated.
  bool _isNonRetryable(int statusCode) =>
      statusCode == 400 ||
      statusCode == 401 ||
      statusCode == 402 ||
      statusCode == 403;
}
