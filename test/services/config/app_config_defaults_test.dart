import 'dart:convert';

import 'package:ardrive/services/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppConfig sync tuning fields', () {
    test('fall back to safe defaults when absent from stored config JSON',
        () {
      // Simulates a config persisted by an older app version (configVersion 3
      // era) that predates the sync tuning fields.
      final config = AppConfig.fromJson(const {
        'allowedDataItemSizeForTurbo': 100000,
        'stripePublishableKey': '',
      });

      expect(config.maxConcurrentDriveSyncs, 15);
      expect(config.driveHistoryGqlPageSize, 100);
    });

    test('round-trips through toJson/fromJson', () {
      final config = AppConfig(
        allowedDataItemSizeForTurbo: 100000,
        stripePublishableKey: '',
        maxConcurrentDriveSyncs: 8,
        driveHistoryGqlPageSize: 500,
      );

      // Round-trip through a real encode/decode cycle: AppConfig's toJson
      // embeds SelectedGateway as an object (no explicitToJson), which only
      // becomes a map through jsonEncode — matching how configs are stored.
      final restored = AppConfig.fromJson(
          json.decode(json.encode(config)) as Map<String, dynamic>);

      expect(restored.maxConcurrentDriveSyncs, 8);
      expect(restored.driveHistoryGqlPageSize, 500);
    });
  });
}
