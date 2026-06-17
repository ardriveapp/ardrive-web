import 'package:ario_sdk/ario_sdk.dart';

/// import stub if we cant use web
import 'package:ario_sdk/src/implementations/ario_sdk_web_stub.dart'
    if (dart.library.html) 'package:ario_sdk/src/implementations/ario_sdk_web.dart';

class ArioSDKFactory {
  static ArioSDK? _instance;

  /// Returns a shared instance of the Ario SDK.
  /// The SDK caches gateway lists and other data internally,
  /// so reusing the same instance avoids redundant RPC calls.
  ArioSDK create() {
    return _instance ??= ArioSDKWeb();
  }
}
