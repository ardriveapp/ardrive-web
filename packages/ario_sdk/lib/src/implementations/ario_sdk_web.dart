@JS('ario')
library ario;

import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:js_util';

import 'package:ario_sdk/ario_sdk.dart';
import 'package:js/js.dart';

class ArioSDKWeb implements ArioSDK {
  List<Gateway>? _cachedGateways;

  List<ARNSRecord> _cachedARNSRecords = [];
  Map<String, List<ARNSUndername>> _cachedUndernames = {};

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

  @override
  Future setUndername({
    required String jwtString,
    required String txId,
    required String domain,
    String undername = '@',
  }) {
    final arnsUndername = ARNSUndername(
      record: AntRecord(transactionId: txId, ttlSeconds: 3600),
      name: undername,
      domain: domain,
    );

    return _setARNSImpl(jwtString, arnsUndername);
  }

  @override
  Future<ARNSRecord> getARNSRecord(String jwtString, String domain) {
    return Future.value(
      ARNSRecord(
        domain: 'thiago',
        processId: 'IyjqOErJOwAhVNCaDfDmZAMJHsyYM-vdV-algNqWF1M',
      ),
    );
    // return _getARNSRecordsImpl(jwtString, domain);
  }

  @override
  Future<List<ARNSRecord>> getARNSRecords(String jwtString) async {
    if (_cachedARNSRecords.isNotEmpty) {
      return _cachedARNSRecords;
    }

    _cachedARNSRecords = await Future.value([
      ARNSRecord(
        domain: 'thiago',
        processId: 'IyjqOErJOwAhVNCaDfDmZAMJHsyYM-vdV-algNqWF1M',
      ),
      ARNSRecord(
        domain: 'thiago2',
        processId: 'wU3baSpUTh8E-oDI-mLezVsj21WJwuf7ftoXYhHWYbA',
      ),
    ]);

    return _cachedARNSRecords;
  }

  @override
  Future<List<ARNSUndername>> getUndernames(
      String jwtString, ARNSRecord record) async {
    if (_cachedUndernames.containsKey(record.domain) &&
        _cachedUndernames[record.domain]!.isNotEmpty) {
      return _cachedUndernames[record.domain]!;
    }

    _cachedUndernames[record.domain] =
        await _getUndernamesImpl(jwtString, record);

    return _cachedUndernames[record.domain]!;
  }

  @override
  Future<void> fetchUndernames(String jwtString, ARNSRecord record) async {
    _cachedUndernames[record.domain] = [];

    _cachedUndernames[record.domain] = (await getUndernames(jwtString, record));
  }
}

@JS('setARNS')
external Object _setARNS(String jwtString, txId, domain, String undername);

Future<dynamic> _setARNSImpl(String jwtString, ARNSUndername undername) async {
  final promise = _setARNS(
    jwtString,
    undername.record.transactionId,
    undername.domain,
    undername.name,
  );

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

@JS('getUndernames')
external Object _getUndernames(String jwtString, String domain);

Future<List<ARNSUndername>> _getUndernamesImpl(
    String jwtString, ARNSRecord arnsRecord) async {
  final promise = _getUndernames(jwtString, arnsRecord.processId);
  final stringified = await promiseToFuture(promise);

  final jsonParsed = jsonDecode(stringified) as Map<String, dynamic>;

  final undernames = <ARNSUndername>[];

  for (var item in jsonParsed.keys) {
    final antRecord = AntRecord(
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
