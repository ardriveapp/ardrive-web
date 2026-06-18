import 'dart:async';

import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/snapshots/snapshot_item.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:http/http.dart' as http;

class SnapshotValidationService {
  final ConfigService _configService;
  final ArioSDK _arioSDK;

  static const _headTimeout = Duration(seconds: 10);
  static const _retryDelay = Duration(milliseconds: 500);
  static const _garListTimeout = Duration(seconds: 5);

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

    final futures = snapshotItems.map((snapshotItem) async {
      try {
        final isValid = await _validateSnapshot(snapshotItem.txId, primaryUrl);

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
    });

    await Future.wait(futures);

    return snapshotsVerified;
  }

  /// Validates a snapshot is available on at least one gateway.
  ///
  /// 1. Try primary gateway with 1 retry on transient errors
  /// 2. If primary fails, try 1 fallback gateway from the GAR list
  /// 3. Accept if ANY gateway returns 200
  Future<bool> _validateSnapshot(String txId, String primaryUrl) async {
    // 1. Try primary gateway (with 1 retry)
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await http
            .head(Uri.parse('$primaryUrl/$txId'))
            .timeout(_headTimeout);

        // 200 = available, 302 = gateway knows about it (redirecting to sandbox URL)
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

        logger.d(
          'Snapshot $txId HEAD attempt ${attempt + 1} '
          'returned ${response.statusCode}',
        );
      } on TimeoutException {
        logger.d('Snapshot $txId HEAD attempt ${attempt + 1} timed out');
      } catch (e) {
        logger.d('Snapshot $txId HEAD attempt ${attempt + 1} error: $e');
      }

      // Retry after brief delay (skip delay on last attempt)
      if (attempt == 0) {
        await Future.delayed(_retryDelay);
      }
    }

    // 2. Primary failed — try 1 fallback gateway
    try {
      final gateways = await _arioSDK
          .getGateways()
          .timeout(_garListTimeout, onTimeout: () => <Gateway>[]);

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
      statusCode == 400 || statusCode == 401 || statusCode == 403;
}
