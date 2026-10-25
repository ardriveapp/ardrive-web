// ignore_for_file: avoid_web_libraries_in_flutter

@JS('ario')
library ario;

import 'dart:async';
import 'dart:convert';
import 'dart:js_util';

import 'package:ario_sdk/ario_sdk.dart';
import 'package:js/js.dart';

class ArioSDKWeb implements ArioSDK {
  Set<Gateway>? _cachedGateways;

  @override
  Future<List<Gateway>> getGateways() async {
    try {
      if (_cachedGateways != null) {
        return _cachedGateways!.toList();
      }
      _cachedGateways = (await getGatewaysList()).toSet();
      return _cachedGateways!.toList();
    } catch (e) {
      throw GetGatewaysException(e.toString());
    }
  }

  @override
  Future<String> getARIOTokens(String address) async {
    try {
      final tokens = await _getARIOTokensImpl(address);

      return tokens;
    } catch (e) {
      throw GetIOTokensException(e.toString());
    }
  }

  @override
  Future<PrimaryNameDetails> getPrimaryNameDetails(
      String address, bool getLogo) async {
    final primaryName = await _getPrimaryNameImpl(address, getLogo);

    return primaryName;
  }

  @override
  Future<void> reinitialize({
    String? rpcUrl,
    String? coreProgramId,
    String? garProgramId,
    String? arnsProgramId,
    String? antProgramId,
  }) async {
    await promiseToFuture(_reinitArioSDK(
      rpcUrl,
      coreProgramId,
      garProgramId,
      arnsProgramId,
      antProgramId,
    ));
    _cachedGateways = null;
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

@JS('getARIOTokens')
external Object _getARIOTokens(String address);

Future<dynamic> _getARIOTokensImpl(String address) async {
  final promise = _getARIOTokens(address);
  final stringified = await promiseToFuture(promise);

  return stringified.toString();
}

@JS('getPrimaryNameAndLogo')
external Object _getPrimaryNameAndLogo(String address, bool getLogo);

Future<PrimaryNameDetails> _getPrimaryNameImpl(
    String address, bool getLogo) async {
  final promise = _getPrimaryNameAndLogo(address, getLogo);
  final stringified = await promiseToFuture(promise);

  final json = jsonDecode(stringified);

  if (json['primaryName'] == null) {
    throw PrimaryNameNotFoundException(
        'Primary name not found for address $address');
  }

  return PrimaryNameDetails(
    primaryName: json['primaryName']['name'],
    logo: json['antInfo']?['Logo'],
    recordId: json['arnsRecord']?['processId'],
  );
}

@JS('reinitArioSDK')
external Object _reinitArioSDK(
  String? rpcUrl,
  String? coreProgramId,
  String? garProgramId,
  String? arnsProgramId,
  String? antProgramId,
);
