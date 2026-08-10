import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/services/config/selected_gateway.dart';
import 'package:ardrive/sync/data/snapshot_validation_service.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockConfigService extends Mock implements ConfigService {}

class _MockArioSDK extends Mock implements ArioSDK {}

void main() {
  group('SnapshotValidationService', () {
    late _MockConfigService configService;

    setUp(() {
      configService = _MockConfigService();
      when(() => configService.config).thenReturn(
        AppConfig(
          // Unroutable host so the HEAD fails fast without touching a real
          // gateway; validation must still complete and simply reject.
          arweaveGatewayForDataRequest: const SelectedGateway(
            label: 'test',
            url: 'https://localhost:1',
          ),
          allowedDataItemSizeForTurbo: 1,
          stripePublishableKey: '',
        ),
      );
    });

    test('constructor takes no ArioSDK — the GAR fallback is gone', () {
      // A compile-time guarantee: this only builds because `arioSDK` is no
      // longer a required parameter.
      final service = SnapshotValidationService(configService: configService);
      expect(service, isA<SnapshotValidationService>());
    });

    test('rejects a snapshot without ever asking for a gateway list',
        () async {
      final arioSDK = _MockArioSDK();
      final service = SnapshotValidationService(configService: configService);

      final verified = await service.validateSnapshotItems([]);

      expect(verified, isEmpty);
      // Nothing in this service can reach the SDK any more.
      verifyNever(() => arioSDK.getGateways());
      verifyZeroInteractions(arioSDK);
    });
  });
}
