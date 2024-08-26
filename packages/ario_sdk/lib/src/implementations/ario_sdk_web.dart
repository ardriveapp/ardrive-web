// ignore_for_file: avoid_web_libraries_in_flutter

@JS('ario')
library ario;

import 'dart:convert';
import 'dart:js_util';

import 'package:ario_sdk/ario_sdk.dart';
import 'package:ario_sdk/src/exceptions.dart';
import 'package:js/js.dart';

class ArioSDKWeb implements ArioSDK {
  List<Gateway>? _cachedGateways;

  @override
  Future<List<Gateway>> getGateways() async {
    try {
      if (_cachedGateways != null) {
        return _cachedGateways!;
      }
      _cachedGateways = await getGatewaysList();
      return _cachedGateways!;
    } catch (e) {
      throw GetGatewaysException(e.toString());
    }
  }

  @override
  Future<String> getIOTokens(String address) async {
    try {
      final tokens = await _getIOTokensImpl(address);

      return tokens;
    } catch (e) {
      throw GetIOTokensException(e.toString());
    }
  }
}

@JS('getGateways')
external Object _getGateways();

Future<List<Gateway>> getGatewaysList() async {
  final promise = _getGateways();
  final stringifiedJson = await promiseToFuture(promise);

  final gateways = <Gateway>[];

  final list = jsonDecode(stringifiedJson);

  for (var item in list) {
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
