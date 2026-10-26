import 'dart:convert';

import 'package:ardrive/services/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stored configs win over the asset config until its `configVersion` grows
/// (CLAUDE.md, "App Flavors & Config Resolution"), so a publication setting
/// has to come from code when a stored config predates its key.
void main() {
  const storedBeforeTheKeys = {
    'allowedDataItemSizeForTurbo': 107520,
    'stripePublishableKey': 'pk',
    'defaultArweaveGatewayForDataRequest': {
      'label': 'My gateway',
      'url': 'https://my.gateway.example',
    },
  };

  test('publications are on ardrive.net, whatever the data gateway', () {
    final config = AppConfig.fromJson(Map.of(storedBeforeTheKeys));
    expect(
        config.arweaveGatewayForDataRequest.url, 'https://my.gateway.example');
    expect(config.publicationGatewayUrl, 'https://ardrive.net');
  });

  test('no wallet is an official publisher unless a config names it', () {
    expect(
        AppConfig.fromJson(Map.of(storedBeforeTheKeys))
            .officialPublisherAddresses,
        isEmpty);
    final named = AppConfig.fromJson({
      ...storedBeforeTheKeys,
      'officialPublisherAddresses': ['ADDRESS'],
    });
    expect(named.officialPublisherAddresses, ['ADDRESS']);
    // As it is stored: encoded, then read back.
    final stored = json.decode(json.encode(named.toJson()));
    expect(AppConfig.fromJson(stored).officialPublisherAddresses, ['ADDRESS']);
  });
}
