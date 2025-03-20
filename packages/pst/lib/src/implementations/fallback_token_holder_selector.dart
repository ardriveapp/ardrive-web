import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:pst/pst.dart';
import 'package:pst/src/implementations/contract_token_holder_selector.dart';

/// A fallback implementation of [TokenHolderSelector] that tries multiple strategies
/// in sequence until one succeeds.
///
/// This implementation will:
/// 1. First try to get token holders from ArioSDK
/// 2. If that fails, fall back to reading from the contract directly
class FallbackTokenHolderSelector implements TokenHolderSelector {
  final TokenHolderSelector _primarySelector;
  final TokenHolderSelector _fallbackSelector;

  FallbackTokenHolderSelector({
    required TokenHolderSelector primarySelector,
    required TokenHolderSelector fallbackSelector,
  })  : _primarySelector = primarySelector,
        _fallbackSelector = fallbackSelector;

  /// Creates a new instance with the standard ArDrive implementation.
  factory FallbackTokenHolderSelector.create({
    required ArioSDK arioSDK,
    required ContractOracle contractOracle,
  }) {
    return FallbackTokenHolderSelector(
      primarySelector: ArDriveContractTokenHolderSelector(arioSDK),
      fallbackSelector: ContractTokenHolderSelector(contractOracle),
    );
  }

  @override
  Future<ArweaveAddress> selectTokenHolder({double? testingRandom}) async {
    try {
      debugPrint('Attempting to select token holder using primary selector...');
      return await _primarySelector.selectTokenHolder(
          testingRandom: testingRandom);
    } catch (e) {
      debugPrint('Primary selector failed: $e');
      debugPrint('Falling back to contract-based selector...');
      return await _fallbackSelector.selectTokenHolder(
          testingRandom: testingRandom);
    }
  }
}
