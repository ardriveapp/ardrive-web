@JS('ario')
library ario;

import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:js_util';

import 'package:ario_sdk/ario_sdk.dart';
import 'package:js/js.dart';

class ArioSDKWeb implements ArioSDK {
  List<Gateway>? _cachedGateways;

  @override
  Future<List<Gateway>> getGateways() async {
    if (_cachedGateways != null) {
      return _cachedGateways!;
    }
    _cachedGateways = await getGatewaysList();
    return _cachedGateways!;
  }

  @override
  Future<String> getIOTokens(String address) async {
    final tokens = await _getIOTokensImpl(address);

    return tokens;
  }

}

@JS('getGateways')
external Object _getGateways();

Future<List<Gateway>> getGatewaysList() async {
  final promise = _getGateways();
  final stringified = await promiseToFuture(promise);

  final jsonParsed = jsonDecode(stringified);

  final gateways = <Gateway>[];

  for (var item in jsonParsed['items']) {
    final gateway = Gateway.fromJson(item);
    gateways.add(gateway);
  }

  return gateways;
}

@JS('getIOTokens')
external Object _getIOTokens(String address);

Future<dynamic> _getIOTokensImpl(String address) async {
  final promise = _getIOTokens(address);
  final stringified = await promiseToFuture(promise);

  return stringified.toString();
}