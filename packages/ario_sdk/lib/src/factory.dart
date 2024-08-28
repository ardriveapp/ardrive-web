import 'package:ario_sdk/ario_sdk.dart';

/// import stub if we cant use web
import 'package:ario_sdk/src/implementations/ario_sdk_web_stub.dart'
    if (dart.library.html) 'package:ario_sdk/src/implementations/ario_sdk_web.dart';

class ArioSDKFactory {
  /// Create a new instance of the Ario SDK
  ArioSDK create() {
    return ArioSDKWeb();
  }
}
