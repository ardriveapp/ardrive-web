import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:pst/pst.dart';
import 'package:pst/src/implementations/contract_token_holder_selector.dart';
import 'package:pst/src/implementations/fallback_token_holder_selector.dart';

/// Factory class for creating [TokenHolderSelector] instances.
class TokenHolderSelectorFactory {
  final ArioSDK _arioSDK;
  final ContractOracle _contractOracle;

  TokenHolderSelectorFactory({
    required ArioSDK arioSDK,
    required ContractOracle contractOracle,
  })  : _arioSDK = arioSDK,
        _contractOracle = contractOracle;

  /// Creates a [TokenHolderSelector] with the specified configuration.
  ///
  /// [useFallback] determines whether to use the fallback implementation that tries
  /// multiple strategies in sequence. If true and ArioSDK is supported, it will first try
  /// ArioSDK and fall back to contract-based selection if that fails. If false or ArioSDK
  /// is not supported, it will only use the contract-based implementation.
  TokenHolderSelector create({bool useFallback = true}) {
    if (useFallback && isArioSDKSupportedOnPlatform()) {
      debugPrint('Using fallback token holder selector');

      return FallbackTokenHolderSelector.create(
        arioSDK: _arioSDK,
        contractOracle: _contractOracle,
      );
    }

    debugPrint('Using contract token holder selector');

    return ContractTokenHolderSelector(_contractOracle);
  }
}
