library ario;

import 'package:ario_sdk/ario_sdk.dart';

abstract class ArioSDK {
  /// Get the list of available gateways
  Future<List<Gateway>> getGateways();

  /// Get the amount of IO tokens for the given address
  Future<String> getIOTokens(String address);

  Future<dynamic> setUndername({
    required String jwtString,
    required String txId,
    required String domain,
    String undername = '@',
  });
  Future<ARNSRecord> getARNSRecord(String jwtString, String domain);
  Future<List<ARNSRecord>> getARNSRecords(String jwtString);
  Future<List<ARNSUndername>> getUndernames(
      String jwtString, ARNSRecord record);
  Future<void> fetchUndernames(String jwtString, ARNSRecord record);
}
