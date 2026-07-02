import 'dart:async';

import 'package:ardrive/services/arweave/data_gateway_fallback.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/snapshots/snapshot_item.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:http/http.dart' as http;

class SnapshotValidationService {
  final ConfigService _configService;
  final ArioSDK _arioSDK;

  static const _headTimeout = Duration(seconds: 5);
  static const _garListTimeout = Duration(seconds: 3);
  static const _maxConcurrentValidations = 3;

  /// Shared reference to [DataGatewayFallback] for reading/writing the
  /// gateway cache. Set by SyncRepository before validation runs so both
  /// services share one cache and avoid duplicate Solana RPC calls.
  DataGatewayFallback? gatewayFallback;

  SnapshotValidationService({
    required ConfigService configService,
    required ArioSDK arioSDK,
  })  : _configService = configService,
        _arioSDK = arioSDK;

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

  /// Validates a snapshot is available on at least one gateway.
  ///
  /// 1. Try primary gateway with 1 retry on transient errors
  /// 2. If primary fails, try 1 fallback gateway from the GAR list
  /// 3. Accept if ANY gateway returns 200
  Future<bool> _validateSnapshot(String txId, String primaryUrl) async {
    var primaryWas404 = false;

    // 1. Try primary gateway (1 attempt, no retry — fail fast)
    try {
      final response = await http
          .head(Uri.parse('$primaryUrl/$txId'))
          .timeout(_headTimeout);

      if (response.statusCode == 200 || response.statusCode == 302) {
        return true;
      }

      if (_isNonRetryable(response.statusCode)) {
        logger.w(
          'Snapshot $txId rejected: '
          'non-retryable status ${response.statusCode}',
        );
        return false;
      }

      primaryWas404 = response.statusCode == 404;

      logger.d(
        'Snapshot $txId HEAD returned ${response.statusCode}',
      );
    } on TimeoutException {
      logger.d('Snapshot $txId HEAD timed out');
    } catch (e) {
      logger.d('Snapshot $txId HEAD error: $e');
    }

    // 2. If primary returned 404, the snapshot likely doesn't exist.
    //    Skip the fallback — GAR list requires Solana RPC which may be
    //    unavailable (localhost, rate limits). Fail fast and fall back to GQL.
    if (primaryWas404) {
      logger.w('Snapshot $txId not found on primary (404), skipping fallback');
      return false;
    }

    // 3. Primary had a transient error (timeout, 5xx) — try 1 fallback gateway.
    //    Read the shared gateway cache from DataGatewayFallback. If unavailable,
    //    fetch from Solana RPC once and cache the result (empty on failure).
    try {
      List<Gateway> gateways;
      if (gatewayFallback != null &&
          gatewayFallback!.cachedGateways != null) {
        gateways = gatewayFallback!.cachedGateways!;
      } else {
        try {
          gateways = await _arioSDK
              .getGateways()
              .timeout(_garListTimeout, onTimeout: () => <Gateway>[]);
          // Store in shared cache if available
          if (gatewayFallback != null) {
            gatewayFallback!.cachedGateways = gateways;
          }
        } catch (e) {
          // Solana RPC failed — cache empty list so we don't retry every call
          logger.w('GAR gateway list unavailable, will not retry: $e');
          if (gatewayFallback != null) {
            gatewayFallback!.cachedGateways = [];
          }
          gateways = [];
        }
      }

      if (gateways.isEmpty) return false;

      final primaryHost = Uri.parse(primaryUrl).host;
      final fallback = gateways.firstWhere(
        (gw) => gw.settings.fqdn != primaryHost,
        orElse: () => gateways.first,
      );

      final response = await http
          .head(Uri.parse('https://${fallback.settings.fqdn}/$txId'))
          .timeout(_headTimeout);

      if (response.statusCode == 200 || response.statusCode == 302) {
        logger.i(
          'Snapshot $txId validated via fallback '
          'gateway ${fallback.settings.fqdn}',
        );
        return true;
      }

      logger.w(
        'Snapshot $txId fallback gateway ${fallback.settings.fqdn} '
        'returned ${response.statusCode}',
      );
    } catch (e) {
      logger.w('Snapshot $txId fallback validation failed: $e');
    }

    return false;
  }

  /// Status codes that should not be retried or fallback-rotated.
  bool _isNonRetryable(int statusCode) =>
      statusCode == 400 ||
      statusCode == 401 ||
      statusCode == 402 ||
      statusCode == 403;
}
