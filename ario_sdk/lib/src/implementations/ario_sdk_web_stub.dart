import 'package:ario_sdk/ario_sdk.dart';

class ArioSDKWeb implements ArioSDK {
  @override
  Future<List<Gateway>> getGateways() async {
    throw UnimplementedError();
  }

  @override
  Future<dynamic> getIOTokens(String address) async {
    throw UnimplementedError();
  }
}
