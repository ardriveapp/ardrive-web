import 'dart:convert';

import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/services/config/ario_gateway_detector.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/services/config/selected_gateway.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ConfigFetcher {
  ConfigFetcher({required this.localStore});

  final LocalKeyValueStore localStore;

  @visibleForTesting
  AssetBundle assetBundle = rootBundle;

  Future<AppConfig> fetchConfig(Flavor flavor) async {
    // 1. Load default config from assets.
    final flavorName = _parseFlavorToEnv(flavor);
    final defaultConfigString =
        await assetBundle.loadString('assets/config/$flavorName.json');
    final defaultConfig = AppConfig.fromJson(
        json.decode(defaultConfigString) as Map<String, dynamic>);

    // 2. Load stored config from local storage.
    final storedConfigString = localStore.getString('config');
    if (storedConfigString == null) {
      // New user or no stored config: try to detect AR.IO gateway
      // Cache the result so we don't re-run on every config version bump
      final detectedGateway = await _getCachedOrDetectGateway();

      AppConfig configToUse = defaultConfig;
      if (detectedGateway != null) {
        // Use detected AR.IO gateway for data requests
        configToUse = defaultConfig.copyWith(
          arweaveGatewayForDataRequest: detectedGateway,
        );
        logger.i('Using detected AR.IO gateway: ${detectedGateway.url}');
      }

      await saveConfigOnDevToolsPrefs(configToUse);
      return configToUse;
    }

    AppConfig storedConfig;
    try {
      storedConfig = AppConfig.fromJson(
          json.decode(storedConfigString) as Map<String, dynamic>);
    } catch (e) {
      logger.e('Error decoding stored config, falling back to default', e);
      // The stored config is malformed. Overwrite it with the default.
      await saveConfigOnDevToolsPrefs(defaultConfig);
      return defaultConfig;
    }

    // 3. Compare versions and replace the stored config if it's outdated.
    // We use `?? 1` to handle old configs that don't have a version number.
    final storedVersion = storedConfig.configVersion ?? 1;
    final defaultVersion = defaultConfig.configVersion ?? 1;

    if (storedVersion < defaultVersion) {
      // The stored config is from a previous release. Replace it.
      // Any developer-specific customizations will be reset, which is acceptable.
      await saveConfigOnDevToolsPrefs(defaultConfig);
      return defaultConfig;
    }

    // The stored config is up-to-date.
    return storedConfig;
  }

  String _parseFlavorToEnv(Flavor flavor) {
    switch (flavor) {
      case Flavor.production:
        return 'prod';
      case Flavor.development:
        return 'dev';
      case Flavor.staging:
        return 'staging';
    }
  }

  Future<void> saveConfigOnDevToolsPrefs(AppConfig config) async {
    await localStore.putString('config', json.encode(config.toJson()));
  }

  Future<void> resetDevToolsPrefs() async {
    await localStore.remove('config');
  }

  /// Returns a cached gateway detection result, or runs detection once
  /// and caches the result for all future loads.
  /// Cache key includes the hostname to handle users visiting from
  /// different domains (e.g., app.ardrive.io vs ardrive.ar.io).
  Future<SelectedGateway?> _getCachedOrDetectGateway() async {
    final hostname = _getCurrentHostname();
    final cacheKey = 'arIOGatewayDetectionResult_$hostname';
    final cached = localStore.getString(cacheKey);
    if (cached != null) {
      // Already ran detection before
      if (cached.isEmpty) return null; // not a gateway
      try {
        final data = json.decode(cached) as Map<String, dynamic>;
        return SelectedGateway(
          label: data['label'] as String,
          url: data['url'] as String,
        );
      } catch (_) {
        // Malformed cache entry — clear and fall through to re-detect
        await localStore.remove(cacheKey);
      }
    }

    // First time or cleared malformed cache: run detection and cache result
    final detected = await ArIOGatewayDetector.detectArIOGateway();
    if (detected != null) {
      await localStore.putString(
        cacheKey,
        json.encode({'label': detected.label, 'url': detected.url}),
      );
    } else {
      // Cache negative result so we don't re-run for this hostname
      await localStore.putString(cacheKey, '');
    }
    return detected;
  }

  String _getCurrentHostname() {
    try {
      // ignore: avoid_web_libraries_in_flutter
      return Uri.base.host;
    } catch (_) {
      return 'unknown';
    }
  }
}
