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
        final snapshotValidation = await http.head(
          Uri.parse(
              '${appConfig.defaultArweaveGatewayForDataRequest.url}/${snapshotItem.txId}'),
        );

        logger.d('Validating snapshot ${snapshotItem.txId}');

        if (snapshotValidation.statusCode == 200) {
          if (snapshotValidation.headers['content-length'] != null) {
            int lenght =
                int.parse(snapshotValidation.headers['content-length']!);

            final headers = {
              'Range': 'bytes=${lenght - 8}-$lenght',
            };

            final validationRequest = await http.get(
              Uri.parse(
                  '${appConfig.defaultArweaveGatewayForDataRequest.url}/${snapshotItem.txId}'),
              headers: headers,
            );

            logger.d(
                'Validation request status code: ${validationRequest.statusCode}');
          }
          logger.d('Snapshot ${snapshotItem.txId} is valid');

          snapshotsVerified.add(snapshotItem);
        }
      } catch (e) {
        logger.w('Error while validating snapshot. ${snapshotItem.txId}');
      }
    });

    await Future.wait(futures);

    snapshotItems.clear();
    snapshotItems = snapshotsVerified;

    return snapshotItems;
  }
}
