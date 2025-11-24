import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/snapshots/snapshot_item.dart';
import 'package:http/http.dart' as http;

class SnapshotValidationService {
  final ConfigService _configService;

  SnapshotValidationService({
    required ConfigService configService,
  }) : _configService = configService;

  Future<List<SnapshotItem>> validateSnapshotItems(
    List<SnapshotItem> snapshotItems,
  ) async {
    List<SnapshotItem> snapshotsVerified = [];

    final futures = snapshotItems.map((snapshotItem) async {
      final appConfig = _configService.config;

      try {
        const validationTimeout = Duration(seconds: 10);

        final snapshotValidation = await http
            .head(
          Uri.parse(
              '${appConfig.defaultArweaveGatewayForDataRequest.url}/${snapshotItem.txId}'),
        )
            .timeout(
          validationTimeout,
          onTimeout: () {
            logger.w('HEAD request timeout for snapshot ${snapshotItem.txId}');
            return http.Response('', 408); // Request Timeout
          },
        );

        logger.d(
            'HEAD request for snapshot ${snapshotItem.txId}: ${snapshotValidation.statusCode}');

        if (snapshotValidation.statusCode != 200) {
          logger.w(
              'Snapshot ${snapshotItem.txId} failed HEAD validation: ${snapshotValidation.statusCode}');
          return; // Skip this snapshot
        }

        final contentLengthHeader = snapshotValidation.headers['content-length'];
        if (contentLengthHeader == null) {
          logger.w(
              'Snapshot ${snapshotItem.txId} has no Content-Length header');
          return; // Skip snapshot
        }

        int length = int.parse(contentLengthHeader);

        // Validate file size is reasonable (1KB - 500MB)
        if (length < 1024) {
          logger.w('Snapshot ${snapshotItem.txId} is too small: $length bytes');
          return; // Skip snapshot
        }

        if (length > 500 * 1024 * 1024) {
          // 500 MB
          logger.w('Snapshot ${snapshotItem.txId} is too large: $length bytes');
          return; // Skip snapshot
        }

        final headers = {
          'Range': 'bytes=${length - 8}-$length',
        };

        final validationRequest = await http
            .get(
          Uri.parse(
              '${appConfig.defaultArweaveGatewayForDataRequest.url}/${snapshotItem.txId}'),
          headers: headers,
        )
            .timeout(
          validationTimeout,
          onTimeout: () {
            logger.w(
                'Range request timeout for snapshot ${snapshotItem.txId}');
            return http.Response('', 408);
          },
        );

        logger.d(
            'Range request for snapshot ${snapshotItem.txId}: ${validationRequest.statusCode}');

        // Check if range request succeeded (206 Partial Content or 200 OK)
        if (validationRequest.statusCode != 206 &&
            validationRequest.statusCode != 200) {
          logger.w(
              'Snapshot ${snapshotItem.txId} failed range validation: ${validationRequest.statusCode}');
          return; // Skip this snapshot
        }

        // Validate response has content
        if (validationRequest.body.isEmpty) {
          logger.w('Snapshot ${snapshotItem.txId} returned empty response');
          return; // Skip snapshot
        }

        // Only log and add if all validations pass
        logger.d(
            'Snapshot ${snapshotItem.txId} passed all validations (size: $length bytes)');
        snapshotsVerified.add(snapshotItem);
      } catch (e, stackTrace) {
        logger.e(
            'Error while validating snapshot ${snapshotItem.txId}',
            e,
            stackTrace);
      }
    });

    await Future.wait(futures);

    snapshotItems.clear();
    snapshotItems = snapshotsVerified;

    return snapshotItems;
  }
}
