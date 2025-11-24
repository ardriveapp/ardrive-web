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

        // Accept snapshot if HEAD request succeeds
        if (snapshotValidation.statusCode == 200) {
          logger.d('Snapshot ${snapshotItem.txId} is valid');
          snapshotsVerified.add(snapshotItem);
        } else {
          logger.w(
              'Snapshot ${snapshotItem.txId} failed validation: ${snapshotValidation.statusCode}');
        }
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
