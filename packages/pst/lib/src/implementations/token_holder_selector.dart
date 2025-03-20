import 'package:ardrive_utils/ardrive_utils.dart';

/// Abstract class defining the interface for selecting a token holder.
///
/// This interface provides a contract for different implementations to select
/// a token holder based on various criteria (e.g., contract balances, vault data).
abstract class TokenHolderSelector {
  /// Selects a token holder based on the implementation's criteria.
  ///
  /// [testingRandom] is an optional parameter used for deterministic testing.
  /// When provided, it should be used instead of generating a random number.
  Future<ArweaveAddress> selectTokenHolder({double? testingRandom});
}
