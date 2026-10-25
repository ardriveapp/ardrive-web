library ario;

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
}
