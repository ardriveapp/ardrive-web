import 'package:ario_sdk/ario_sdk.dart';

class ArioSDKWeb implements ArioSDK {
  @override
  Future<List<Gateway>> getGateways() async {
    throw UnimplementedError();
  }

  @override
  Future<String> getIOTokens(String address) async {
    throw UnimplementedError();
  }
}
