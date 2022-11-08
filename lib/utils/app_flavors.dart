import 'package:ardrive/services/config/config_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AppFlavors {
  Future<Flavor> getAppFlavor() async {
    String? flavor =
        await const MethodChannel('flavor').invokeMethod<String>('getFlavor');

    debugPrint('Current flavor: $flavor');

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
