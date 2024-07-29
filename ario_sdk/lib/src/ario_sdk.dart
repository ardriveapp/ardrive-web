// ignore_for_file: avoid_web_libraries_in_flutter

@JS('ario')
library ario;

import 'dart:convert';
import 'dart:js_util';

import 'package:ario_sdk/src/models/gateway.dart';
import 'package:flutter/material.dart';
import 'package:js/js.dart';

abstract class ArioSDK {
  Future<List<Gateway>> getGateways();
  Future<dynamic> getIOTokens(String address);
}

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
  Future<dynamic> getIOTokens(String address) async {
    final tokens = await _getIOTokensImpl(address);

    debugPrint('Loaded IO tokens for $address');

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
