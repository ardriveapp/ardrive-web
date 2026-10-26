// ignore_for_file: avoid_web_libraries_in_flutter

@JS('ario')
library ario;

import 'dart:async';
import 'dart:convert';
import 'dart:js_util';
import 'dart:typed_data';

import 'package:ario_sdk/ario_sdk.dart';
import 'package:js/js.dart';

class ArioSDKWeb implements ArioSDK {
  ArioSDKWeb() {
    try {
      _setSolanaAccountListener(allowInterop((String address) {
        _accountChanges.add(address.isEmpty ? null : address);
      }));
      _setSolanaWalletsListener(allowInterop((String walletsJson) {
        _walletsChanges.add(_parseWallets(walletsJson));
      }));
    } catch (_) {
      // The bridge script is not on this page (a publication): no wallets.
    }
  }

  Set<Gateway>? _cachedGateways;
  final _accountChanges = StreamController<String?>.broadcast();
  final _walletsChanges = StreamController<List<SolanaWalletInfo>>.broadcast();

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

  @override
  Future<ArioNetworkConfig> getNetworkConfig() async =>
      ArioNetworkConfig.fromJson(jsonDecode(_getArioConfig()));

  @override
  List<SolanaWalletInfo> listSolanaWallets() =>
      _parseWallets(_listSolanaWallets());

  static List<SolanaWalletInfo> _parseWallets(String json) => [
        for (final item in jsonDecode(json) as List)
          SolanaWalletInfo.fromJson(item as Map<String, dynamic>),
      ];

  @override
  Stream<List<SolanaWalletInfo>> get solanaWalletsChanges =>
      _walletsChanges.stream;

  @override
  Future<String?> connectSolanaWallet(String name, {bool silent = false}) async {
    final String address =
        await promiseToFuture(_connectSolanaWallet(name, silent));
    return address.isEmpty ? null : address;
  }

  @override
  Future<void> disconnectSolanaWallet() =>
      promiseToFuture(_disconnectSolanaWallet());

  @override
  String? get connectedSolanaAddress => _nonEmpty(_connectedSolanaAddress());

  @override
  String? get connectedSolanaWalletName =>
      _nonEmpty(_connectedSolanaWalletName());

  static String? _nonEmpty(String value) => value.isEmpty ? null : value;

  @override
  Stream<String?> get solanaAccountChanges => _accountChanges.stream;

  @override
  Future<Uint8List> solanaSignMessage(Uint8List message) async {
    final String signature = await promiseToFuture(
      _solanaSignMessage(base64Encode(message), 'base64'),
    );
    return base64Decode(signature);
  }

  @override
  Future<String> solanaSignTransaction(String transactionBase64) =>
      promiseToFuture(_solanaSignTransaction(transactionBase64));

  @override
  Future<List<ArNSNameData>> getArNSNamesForAddress(String address) async {
    final String json = await promiseToFuture(_getArNSNamesForAddress(address));
    return [
      for (final item in jsonDecode(json) as List)
        ArNSNameData.fromJson(item as Map<String, dynamic>),
    ];
  }

  @override
  Future<Map<String, ANTSummary>> getANTSummaries(
    List<String> processIds,
  ) async {
    final String json =
        await promiseToFuture(_getANTSummaries(jsonEncode(processIds)));
    return (jsonDecode(json) as Map<String, dynamic>).map(
      (id, value) =>
          MapEntry(id, ANTSummary.fromJson(value as Map<String, dynamic>)),
    );
  }

  @override
  Future<List<ANTUndernameRecord>> getANTRecords(String processId) async {
    final String json = await promiseToFuture(_getANTRecords(processId));
    return [
      for (final item in jsonDecode(json) as List)
        ANTUndernameRecord.fromJson(item as Map<String, dynamic>),
    ];
  }

  @override
  Future<String> setRecordAsController({
    required String processId,
    required String undername,
    required String transactionId,
    required int ttlSeconds,
  }) =>
      promiseToFuture(_setRecordAsController(
        processId,
        undername,
        transactionId,
        ttlSeconds,
      ));

  @override
  Future<String> removeRecordAsController({
    required String processId,
    required String undername,
  }) =>
      promiseToFuture(_removeRecordAsController(processId, undername));

  @override
  Future<BigInt> getSolBalanceLamports(String address) async {
    final String lamports =
        await promiseToFuture(_getSolBalanceLamports(address));
    return BigInt.parse(lamports);
  }

  @override
  Future<ControllerFeeEstimate> estimateControllerFee({
    required String processId,
    required ControllerWrite write,
    required String undername,
  }) async {
    final String json = await promiseToFuture(
      _estimateControllerFee(processId, write.workflow, undername),
    );
    return ControllerFeeEstimate.fromJson(jsonDecode(json));
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

@JS('getArioConfig')
external String _getArioConfig();

@JS('listSolanaWallets')
external String _listSolanaWallets();

@JS('connectSolanaWallet')
external Object _connectSolanaWallet(String name, bool silent);

@JS('disconnectSolanaWallet')
external Object _disconnectSolanaWallet();

@JS('connectedSolanaAddress')
external String _connectedSolanaAddress();

@JS('connectedSolanaWalletName')
external String _connectedSolanaWalletName();

@JS('setSolanaAccountListener')
external void _setSolanaAccountListener(void Function(String) listener);

@JS('setSolanaWalletsListener')
external void _setSolanaWalletsListener(void Function(String) listener);

@JS('solanaSignMessage')
external Object _solanaSignMessage(String data, String encoding);

@JS('solanaSignTransaction')
external Object _solanaSignTransaction(String transactionBase64);

@JS('getArNSNamesForAddress')
external Object _getArNSNamesForAddress(String address);

@JS('getANTSummaries')
external Object _getANTSummaries(String processIdsJson);

@JS('getANTRecords')
external Object _getANTRecords(String processId);

@JS('setRecordAsController')
external Object _setRecordAsController(
  String processId,
  String undername,
  String transactionId,
  int ttlSeconds,
);

@JS('removeRecordAsController')
external Object _removeRecordAsController(String processId, String undername);

@JS('getSolBalanceLamports')
external Object _getSolBalanceLamports(String address);

@JS('estimateControllerFee')
external Object _estimateControllerFee(
  String processId,
  String workflow,
  String undername,
);
