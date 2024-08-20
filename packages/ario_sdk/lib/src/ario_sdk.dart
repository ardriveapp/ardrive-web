@JS('ario')
library ario;

import 'package:ario_sdk/src/models/gateway.dart';
import 'package:js/js.dart';

abstract class ArioSDK {
  Future<List<Gateway>> getGateways();
  Future<dynamic> getIOTokens(String address);
}
