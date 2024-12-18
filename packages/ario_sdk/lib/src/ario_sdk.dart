library ario;

import 'package:ario_sdk/ario_sdk.dart';
import 'package:ario_sdk/src/models/response_object.dart';

abstract class ArioSDK {
  /// Get the list of available gateways
  Future<List<Gateway>> getGateways();

  /// Get the amount of IO tokens for the given address
  Future<String> getIOTokens(String address);

  Future<List<ARNSProcessData>> getAntRecordsForWallet(String address);

  Future<List<ARNSUndername>> getUndernames(String jwtString, ANTRecord record,
      {bool update = false});

  Future<dynamic> setUndername({
    required String jwtString,
    required String txId,
    required String domain,
    String undername = '@',
  });

  Future<dynamic> setUndernameWithArConnect({
    required String txId,
    required String domain,
    String undername = '@',
  });

  /// Get the primary name for the given address
  ///
  /// Throws [PrimaryNameNotFoundException] if the primary name is not found
  Future<PrimaryNameDetails> getPrimaryNameDetails(
    String address,
    bool getLogo,
  );
}
