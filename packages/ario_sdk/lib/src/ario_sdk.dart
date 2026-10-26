library ario;

import 'dart:typed_data';

import 'package:ario_sdk/ario_sdk.dart';

abstract class ArioSDK {
  /// Get the list of available gateways
  Future<List<Gateway>> getGateways();

  /// Get the amount of IO tokens for the given address
  Future<String> getARIOTokens(String address);

  /// Get the primary name for the given address
  ///
  /// Throws [PrimaryNameNotFoundException] if the primary name is not found
  Future<PrimaryNameDetails> getPrimaryNameDetails(
    String address,
    bool getLogo,
  );

  /// Reinitialize the SDK with new Solana RPC and/or program ID configuration.
  /// Pass null for any parameter to use the SDK default (mainnet).
  /// Clears all cached data.
  Future<void> reinitialize({
    String? rpcUrl,
    String? coreProgramId,
    String? garProgramId,
    String? arnsProgramId,
    String? antProgramId,
  });

  /// The RPC URLs and program IDs of mainnet and devnet, from the SDK, and
  /// which one the bridge is on.
  Future<ArioNetworkConfig> getNetworkConfig();

  // --- The ArNS wallet (Wallet Standard) ---

  /// Installed Solana wallets that can connect, sign messages and sign
  /// transactions. Empty where none injects, as on most phones.
  List<SolanaWalletInfo> listSolanaWallets();

  /// The installed wallets again, whenever one registers late or goes away.
  Stream<List<SolanaWalletInfo>> get solanaWalletsChanges;

  /// Connects the named wallet and returns its address. With [silent], only
  /// an already authorised wallet connects, without a prompt; null when it
  /// isn't.
  Future<String?> connectSolanaWallet(String name, {bool silent = false});

  Future<void> disconnectSolanaWallet();

  /// The connected wallet's address, or null.
  String? get connectedSolanaAddress;

  /// The connected wallet's name, or null.
  String? get connectedSolanaWalletName;

  /// The connected address whenever the wallet switches account; null when
  /// it has none.
  Stream<String?> get solanaAccountChanges;

  /// The connected wallet's 64-byte ed25519 signature over [message].
  Future<Uint8List> solanaSignMessage(Uint8List message);

  /// Signs a base64 transaction exactly as given; returns it signed, base64.
  Future<String> solanaSignTransaction(String transactionBase64);

  // --- ArNS reads ---

  /// The names [address] owns or controls.
  Future<List<ArNSNameData>> getArNSNamesForAddress(String address);

  /// Owner, controllers and apex record of each ANT, by process ID. ANTs
  /// that don't exist are left out.
  Future<Map<String, ANTSummary>> getANTSummaries(List<String> processIds);

  /// Every record of an ANT, `@` included.
  Future<List<ANTUndernameRecord>> getANTRecords(String processId);

  // --- Controller writes: the connected wallet signs and pays ---

  /// Sets a record with the connected wallet's own transaction and returns
  /// its signature.
  Future<String> setRecordAsController({
    required String processId,
    required String undername,
    required String transactionId,
    required int ttlSeconds,
  });

  /// Removes an undername with the connected wallet's own transaction.
  Future<String> removeRecordAsController({
    required String processId,
    required String undername,
  });

  Future<BigInt> getSolBalanceLamports(String address);

  Future<ControllerFeeEstimate> estimateControllerFee({
    required String processId,
    required ControllerWrite write,
    required String undername,
  });
}
