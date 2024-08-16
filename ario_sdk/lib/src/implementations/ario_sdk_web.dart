@JS('ario')
library ario;

import 'dart:convert';
import 'dart:js_util';

import 'package:ario_sdk/ario_sdk.dart';
import 'package:ario_sdk/src/models/arns_record.dart';
import 'package:flutter/material.dart';
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
  Future<dynamic> getIOTokens(String address) async {
    final tokens = await _getIOTokensImpl(address);

    debugPrint('Loaded IO tokens for $address');

    return tokens;
  }

  @override
  Future setARNS(String jwtString, txId, domain, String undername) {
    return _setARNSImpl(jwtString, txId, domain, undername);
  }

  @override
  Future<ARNSRecord> getARNSRecord(String jwtString, String domain) {
    return Future.value(
      ARNSRecord(
          domain: 'thiago',
          processId: 'IyjqOErJOwAhVNCaDfDmZAMJHsyYM-vdV-algNqWF1M'),
    );
    // return _getARNSRecordsImpl(jwtString, domain);
  }
}

@JS('setARNS')
external Object _setARNS(String jwtString, txId, domain, String undername);

Future<dynamic> _setARNSImpl(
    String jwtString, String txId, String domain, String undername) async {
  final promise = _setARNS(jwtString, txId, domain, undername);
  final stringified = await promiseToFuture(promise);

  return stringified.toString();
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

@JS('getARNSRecord')
external Object _getARNSRecord(String jwtString, String domain);

Future<Map<String, dynamic>> _getARNSRecordsImpl(
    String jwtString, String domain) async {
  final promise = _getARNSRecord(jwtString, domain);
  final stringified = await promiseToFuture(promise);

  return jsonDecode(stringified);
}
