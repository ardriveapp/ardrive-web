// ignore_for_file: avoid_web_libraries_in_flutter

@JS('ario')
library ario;

import 'dart:async';
import 'dart:convert';
import 'dart:js_util';

import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:js/js.dart';

class GetARNSRecordsForWalletException implements Exception {
  final String message;

  GetARNSRecordsForWalletException(this.message);

  @override
  String toString() => message;
}

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
  Future<String> getARIOTokens(String address) async {
    try {
      final tokens = await _getARIOTokensImpl(address);

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
    final arnsUndername = ARNSUndernameFactory.create(
      transactionId: txId,
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
    final arnsUndername = ARNSUndernameFactory.create(
      transactionId: txId,
      name: undername,
      domain: domain,
    );

    return _setARNSImpl('', arnsUndername, true);
  }

  @override
  Future<List<ArNSNameModel>> getArNSNames(String address) async {
    final processes = await _getARNSRecordsForWalletImpl(address);

    List<ArNSNameModel> names = [];

    for (var e in processes) {
      final name = e.names[e.names.keys.first];
      final undernameLimit = name?.undernameLimit;

      if (undernameLimit == null) {
        throw Exception('Under name limit is null');
      }

      e.state.records.removeWhere((key, value) => key == '@');

      names.add(ArNSNameModel(
        name: e.names.keys.first,
        processId: e.names.keys.first,
        records: e.state.records.length,
        undernameLimit: undernameLimit,
      ));
    }

    return names;
  }

  @override
  Future<PrimaryNameDetails> getPrimaryNameDetails(
      String address, bool getLogo) async {
    final primaryName = await _getPrimaryNameImpl(address, getLogo);

    return primaryName;
  }

  @override
  Future createUndername({
    required ARNSUndername undername,
    required bool isArConnect,
    required String txId,
    String? jwtString,
  }) {
    return _setARNSImpl(jwtString, undername, isArConnect);
  }
}

@JS('setARNS')
external Object _setARNS(String? jwtString, String txId, String domain,
    String undername, bool useArConnect);

Future<dynamic> _setARNSImpl(
    String? jwtString, ARNSUndername undername, bool useArConnect) async {
  try {
    debugPrint(
        'undername.record.transactionId: ${undername.record.transactionId}');

    final promise = _setARNS(
      jwtString,
      undername.record.transactionId,
      undername.domain,
      undername.name,
      useArConnect,
    );

    final stringified = await promiseToFuture(promise);

    return stringified.toString();
  } catch (e) {
    throw Exception(e);
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

    final undername = ARNSUndernameFactory.create(
      transactionId: antRecord.transactionId,
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
  try {
    final promise = _getARNSRecordsForWallet(address);
    final stringified = await promiseToFuture(promise)
        .timeout(const Duration(seconds: 60), onTimeout: () {
      throw TimeoutException(
          'Failed to get ARNS records: timeout after 60 seconds');
    });

    final object = ResponseObject.fromJson(jsonDecode(stringified));

    return object.data.values.toList();
  } catch (e) {
    if (e is TimeoutException) {
      throw GetARNSRecordsForWalletException(
          'ARNS records fetch timed out: ${e.message}');
    }

    throw GetARNSRecordsForWalletException(
        'Failed to get ARNS records: ${e.toString()}');
  }
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
