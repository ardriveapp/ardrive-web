import 'package:ario_sdk/ario_sdk.dart';
import 'package:ario_sdk/src/models/response_object.dart';

class ArioSDKWeb implements ArioSDK {
  @override
  Future<List<ARNSProcessData>> getAntRecordsForWallet(String address) {
    // TODO: implement getAntRecordsForWallet
    throw UnimplementedError();
  }

  @override
  Future<List<Gateway>> getGateways() {
    // TODO: implement getGateways
    throw UnimplementedError();
  }

  @override
  Future<String> getIOTokens(String address) {
    // TODO: implement getIOTokens
    throw UnimplementedError();
  }

  @override
  Future<List<ARNSUndername>> getUndernames(String jwtString, ANTRecord record,
      {bool update = false}) {
    // TODO: implement getUndernames
    throw UnimplementedError();
  }

  @override
  Future setUndername(
      {required String jwtString,
      required String txId,
      required String domain,
      String undername = '@'}) {
    // TODO: implement setUndername
    throw UnimplementedError();
  }
}
