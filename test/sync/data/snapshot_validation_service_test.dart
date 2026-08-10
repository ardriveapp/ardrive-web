import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/services/config/selected_gateway.dart';
import 'package:ardrive/sync/data/snapshot_validation_service.dart';
import 'package:ardrive/utils/snapshots/snapshot_item.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockConfigService extends Mock implements ConfigService {}

class _MockArioSDK extends Mock implements ArioSDK {}

/// The only member [SnapshotValidationService] reads off a snapshot item.
///
/// A real [SnapshotItemOnChain] would drag a GraphQL node and a byte source in
/// with it, none of which the validation path touches.
class _FakeSnapshotItem extends Fake implements SnapshotItem {
  @override
  final String txId = 'Iw3hSMB1kQ9Vpp5rUwx5Z4kv7cKzYwzZ_-7QK4mUuTc';
}

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

      // A nonempty list, so validation actually runs: an empty one returns
      // before the loop and would assert nothing at all.
      final verified = await service.validateSnapshotItems([
        _FakeSnapshotItem(),
      ]);

      // The configured gateway is unreachable, so the snapshot is rejected -
      // and on `dev` this is the point where the service would have reached
      // for the GAR list to try a second gateway.
      expect(verified, isEmpty);

      // Vacuous on its own, since the service is never handed this SDK. It is
      // the compile-time signature above that proves the branch is gone; this
      // documents the intent at the call site.
      verifyZeroInteractions(arioSDK);
    });
  });
}
