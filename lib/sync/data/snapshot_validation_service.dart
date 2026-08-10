import 'dart:async';

import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/snapshots/snapshot_item.dart';
import 'package:http/http.dart' as http;

class SnapshotValidationService {
  final ConfigService _configService;

  static const _headTimeout = Duration(seconds: 5);
  static const _maxConcurrentValidations = 3;

  SnapshotValidationService({
    required ConfigService configService,
  }) : _configService = configService;

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
  /// Single HEAD against the configured gateway; anything other than 200/302
  /// rejects the snapshot and sync falls back to GQL for that range, which is
  /// correct (just slower) in every case.
  ///
  /// There is deliberately no GAR fallback here. It only ever ran for
  /// transient errors, and it cost a Solana RPC via `ArioSDK.getGateways()` —
  /// the sync path must not issue one. Rejecting a snapshot is cheap and safe;
  /// paying a Solana round-trip to maybe save a GQL range is not.
  Future<bool> _validateSnapshot(String txId, String primaryUrl) async {
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

      logger.w(
        'Snapshot $txId rejected: HEAD returned ${response.statusCode}, '
        'falling back to GQL for its range',
      );
    } on TimeoutException {
      logger.w('Snapshot $txId rejected: HEAD timed out');
    } catch (e) {
      logger.w('Snapshot $txId rejected: HEAD error: $e');
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
