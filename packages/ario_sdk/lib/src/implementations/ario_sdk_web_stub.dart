import 'dart:typed_data';

import 'package:ario_sdk/ario_sdk.dart';

class ArioSDKWeb implements ArioSDK {
  @override
  Future<List<Gateway>> getGateways() {
    // TODO: implement getGateways
    throw UnimplementedError();
  }

  @override
  Future<String> getARIOTokens(String address) {
    // TODO: implement getARIOTokens
    throw UnimplementedError();
  }

  @override
  Future<PrimaryNameDetails> getPrimaryNameDetails(
    String address,
    bool getLogo,
  ) {
    // TODO: implement getPrimaryName
    throw UnimplementedError();
  }

  @override
  Future<void> reinitialize({
    String? rpcUrl,
    String? coreProgramId,
    String? garProgramId,
    String? arnsProgramId,
    String? antProgramId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ArioNetworkConfig> getNetworkConfig() => throw UnimplementedError();

  @override
  List<SolanaWalletInfo> listSolanaWallets() => const [];

  @override
  Stream<List<SolanaWalletInfo>> get solanaWalletsChanges =>
      const Stream.empty();

  @override
  Future<String?> connectSolanaWallet(String name, {bool silent = false}) =>
      throw UnimplementedError();

  @override
  Future<void> disconnectSolanaWallet() async {}

  @override
  String? get connectedSolanaAddress => null;

  @override
  String? get connectedSolanaWalletName => null;

  @override
  Stream<String?> get solanaAccountChanges => const Stream.empty();

  @override
  Future<Uint8List> solanaSignMessage(Uint8List message) =>
      throw UnimplementedError();

  @override
  Future<String> solanaSignTransaction(String transactionBase64) =>
      throw UnimplementedError();

  @override
  Future<List<ArNSNameData>> getArNSNamesForAddress(String address) =>
      throw UnimplementedError();

  @override
  Future<Map<String, ANTSummary>> getANTSummaries(List<String> processIds) =>
      throw UnimplementedError();

  @override
  Future<List<ANTUndernameRecord>> getANTRecords(String processId) =>
      throw UnimplementedError();

  @override
  Future<String> setRecordAsController({
    required String processId,
    required String undername,
    required String transactionId,
    required int ttlSeconds,
  }) =>
      throw UnimplementedError();

  @override
  Future<String> removeRecordAsController({
    required String processId,
    required String undername,
  }) =>
      throw UnimplementedError();

  @override
  Future<BigInt> getSolBalanceLamports(String address) =>
      throw UnimplementedError();

  @override
  Future<ControllerFeeEstimate> estimateControllerFee({
    required String processId,
    required ControllerWrite write,
    required String undername,
  }) =>
      throw UnimplementedError();
}
