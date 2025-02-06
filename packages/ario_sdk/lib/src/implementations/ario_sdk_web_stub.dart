import 'package:ario_sdk/ario_sdk.dart';

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
  Future<String> getARIOTokens(String address) {
    // TODO: implement getARIOTokens
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

  @override
  Future setUndernameWithArConnect(
      {required String txId, required String domain, String undername = '@'}) {
    // TODO: implement setUndernameWithArConnect
    throw UnimplementedError();
  }

  @override
  Future<List<ArNSNameModel>> getArNSNames(String address) {
    // TODO: implement getArNSNames
    throw UnimplementedError();
  }

  @override
  Future<PrimaryNameDetails> getPrimaryNameDetails(
    String address,
    bool getLogo,
  ) {
    // TODO: implement getPrimaryName
    throw UnimplementedError();
  }

  @override
  Future createUndername({
    required ARNSUndername undername,
    required bool isArConnect,
    required String txId,
    required String jwtString,
  }) {
    // TODO: implement createUndername
    throw UnimplementedError();
  }
}
