import 'package:ario_sdk/ario_sdk.dart';

/// import stub if we cant use web
import 'package:ario_sdk/src/implementations/ario_sdk_web_stub.dart'
    if (dart.library.html) 'package:ario_sdk/src/implementations/ario_sdk_web.dart';
import 'package:flutter/foundation.dart';

class ArioSDKFactory {
  ArioSDK create() {
    if (kIsWeb) {
      return ArioSDKWeb();
    }

    /// Mobile and Desktop platforms are not supported yet.
    throw UnsupportedError('Platform not supported');
  }
}
