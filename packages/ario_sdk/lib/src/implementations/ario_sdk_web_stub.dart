import 'package:ario_sdk/ario_sdk.dart';
import 'package:ario_sdk/src/models/arns_record.dart';

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
  Future setARNS(String jwtString, txId, domain, String undername) {
    // TODO: implement setARNS
    throw UnimplementedError();
  }

  @override
  Future<ARNSRecord> getARNSRecord(String jwtString, String domain) {
    // TODO: implement getARNSRecords
    throw UnimplementedError();
  }
}
