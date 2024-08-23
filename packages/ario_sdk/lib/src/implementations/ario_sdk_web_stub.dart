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

  @override
  Future<ARNSRecord> getARNSRecord(String jwtString, String domain) {
    // TODO: implement getARNSRecords
    throw UnimplementedError();
  }

  @override
  Future<List<ARNSRecord>> getARNSRecords(String jwtString) {
    // TODO: implement getARNSRecords
    throw UnimplementedError();
  }

  @override
  Future setUndername(
      {required String jwtString,
      required String txId,
      required String domain,
      String undername = '@'}) {
    // TODO: implement setARNS
    throw UnimplementedError();
  }

  @override
  Future<List<ARNSUndername>> getUndernames(
      String jwtString, ARNSRecord record) {
    // TODO: implement getUndernames
    throw UnimplementedError();
  }

  @override
  Future<void> fetchUndernames(String jwtString, ARNSRecord record) {
    // TODO: implement fetchUndernames
    throw UnimplementedError();
  }
}
