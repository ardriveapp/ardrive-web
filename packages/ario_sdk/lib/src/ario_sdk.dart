library ario;

import 'package:ario_sdk/src/models/gateway.dart';

abstract class ArioSDK {
  /// Get the list of available gateways
  Future<List<Gateway>> getGateways();

  /// Get the amount of IO tokens for the given address
  Future<String> getIOTokens(String address);
}
