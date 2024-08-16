// ignore_for_file: avoid_web_libraries_in_flutter

@JS('ario')
library ario;

import 'package:ario_sdk/src/models/arns_record.dart';
import 'package:ario_sdk/src/models/gateway.dart';
import 'package:js/js.dart';

abstract class ArioSDK {
  Future<List<Gateway>> getGateways();
  Future<dynamic> getIOTokens(String address);
  Future<dynamic> setARNS(String jwtString, txId, domain, String undername);
  Future<ARNSRecord> getARNSRecord(String jwtString, String domain);
}
