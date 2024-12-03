// ignore_for_file: avoid_web_libraries_in_flutter

@JS('ario')
library ario;

import 'dart:convert';
import 'dart:js_util';

import 'package:ario_sdk/ario_sdk.dart';
import 'package:ario_sdk/src/exceptions.dart';
import 'package:ario_sdk/src/models/response_object.dart';
import 'package:js/js.dart';

class ArioSDKWeb implements ArioSDK {
  Set<Gateway>? _cachedGateways;

  final Map<String, Set<ARNSUndername>> _cachedUndernames = {};

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
  Future<String> getIOTokens(String address) async {
    try {
      final tokens = await _getIOTokensImpl(address);

      return tokens;
    } catch (e) {
      throw GetIOTokensException(e.toString());
    }
  }

  @override
  Future setUndername({
    required String jwtString,
    required String txId,
    required String domain,
    String undername = '@',
  }) {
    final arnsUndername = ARNSUndername(
      record: ARNSRecord(transactionId: txId, ttlSeconds: 3600),
      name: undername,
      domain: domain,
    );

    return _setARNSImpl(
      jwtString,
      arnsUndername,
      false,
    );
  }

  @override
  Future<List<ARNSProcessData>> getAntRecordsForWallet(
    String address,
  ) async {
    final processes = await _getARNSRecordsForWalletImpl(address);

    return processes;
  }

  @override
  Future<List<ARNSUndername>> getUndernames(String jwtString, ANTRecord record,
      {bool update = false}) async {
    if (!update &&
        _cachedUndernames.containsKey(record.domain) &&
        _cachedUndernames[record.domain]!.isNotEmpty) {
      return _cachedUndernames[record.domain]!.toList();
    }

    _cachedUndernames[record.domain] =
        (await _getUndernamesImpl(jwtString, record)).toSet();

    return _cachedUndernames[record.domain]!.toList();
  }

  @override
  Future setUndernameWithArConnect(
      {required String txId,
      required String domain,
      String undername = '@'}) async {
    final arnsUndername = ARNSUndername(
      record: ARNSRecord(transactionId: txId, ttlSeconds: 3600),
      name: undername,
      domain: domain,
    );

    return _setARNSImpl('', arnsUndername, true);
  }

  @override
  Future<String> getPrimaryName(String address) async {
    final primaryName = await _getPrimaryNameImpl(address);

    if (primaryName.contains('Primary name data not found')) {
      throw PrimaryNameNotFoundException(primaryName);
    }

    return primaryName;
  }
}

@JS('setARNS')
external Object _setARNS(
    String jwtString, txId, domain, String undername, bool useArConnect);

Future<dynamic> _setARNSImpl(
    String jwtString, ARNSUndername undername, bool useArConnect) async {
  final promise = _setARNS(
    jwtString,
    undername.record.transactionId,
    undername.domain,
    undername.name,
    useArConnect,
  );

  final stringified = await promiseToFuture(promise);

  return stringified.toString();
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

@JS('getUndernames')
external Object _getUndernames(String jwtString, String domain);

Future<List<ARNSUndername>> _getUndernamesImpl(
    String jwtString, ANTRecord arnsRecord) async {
  final promise = _getUndernames(jwtString, arnsRecord.processId);
  final stringified = await promiseToFuture(promise);

  final jsonParsed = jsonDecode(stringified) as Map<String, dynamic>;

  final undernames = <ARNSUndername>[];

  for (var item in jsonParsed.keys) {
    final antRecord = ARNSRecord(
      transactionId: jsonParsed[item]['transactionId'],
      ttlSeconds: jsonParsed[item]['ttlSeconds'],
    );

    final undername = ARNSUndername(
      record: antRecord,
      name: item,
      domain: arnsRecord.domain,
    );

    undernames.add(undername);
  }

  return undernames;
}

@JS('getARNSRecordsForWallet')
external Object _getARNSRecordsForWallet(String address);

Future<List<ARNSProcessData>> _getARNSRecordsForWalletImpl(
    String address) async {
  final promise = _getARNSRecordsForWallet(address);
  final stringified = await promiseToFuture(promise);

  final object = ResponseObject.fromJson(jsonDecode(stringified));

  return object.data.values.toList();
}

@JS('getPrimaryName')
external Object _getPrimaryName(String address);

Future<String> _getPrimaryNameImpl(String address) async {
  final promise = _getPrimaryName(address);
  final stringified = await promiseToFuture(promise);

  final json = jsonDecode(stringified);

  return json['name'];
}
