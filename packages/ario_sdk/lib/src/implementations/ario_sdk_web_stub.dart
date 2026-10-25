import 'package:ario_sdk/ario_sdk.dart';

class ArioSDKWeb implements ArioSDK {
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
  Future<PrimaryNameDetails> getPrimaryNameDetails(
    String address,
    bool getLogo,
  ) {
    // TODO: implement getPrimaryName
    throw UnimplementedError();
  }

  @override
  Future<void> reinitialize({
    String? rpcUrl,
    String? coreProgramId,
    String? garProgramId,
    String? arnsProgramId,
    String? antProgramId,
  }) {
    throw UnimplementedError();
  }
}
