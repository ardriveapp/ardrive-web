import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AppFlavors {
  Future<Flavor> getAppFlavor() async {
    if (kIsWeb) {
      if (const String.fromEnvironment('environment') == 'prod') {
        return Flavor.production;
      }

      return Flavor.development;
    }

    String? flavor =
        await const MethodChannel('flavor').invokeMethod<String>('getFlavor');

    logger.i('Current flavor: $flavor');

    switch (flavor) {
      case 'production':
        return Flavor.production;
      case 'development':
        return Flavor.development;
      default:
        throw UnsupportedError('$flavor flavor is not supported.');
    }
  }
}
