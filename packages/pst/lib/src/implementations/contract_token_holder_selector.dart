import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:equatable/equatable.dart';
import 'package:pst/pst.dart';
import 'package:pst/src/implementations/token_holder_selector.dart';
import 'package:pst/src/utils.dart';

/// Implementation of [TokenHolderSelector] that selects token holders based on contract data.
///
/// This implementation uses the contract's balances and vault data to determine token holders
/// and their weights for selection.
class ContractTokenHolderSelector implements TokenHolderSelector {
  final ContractOracle _contractOracle;
  CommunityContractData? _communityContractData;
  DateTime? _lastFetchedTime;

  ContractTokenHolderSelector(this._contractOracle);

  @override
  Future<ArweaveAddress> selectTokenHolder({double? testingRandom}) async {
    final contract = await _getCommunityContractData();

    final Map<ArweaveAddress, int> balances = Map.from(contract.balances);
    final vault = contract.vault;

    // Get the total number of token holders
    int total = 0;
    for (final addr in balances.keys) {
      total += balances[addr]!;
    }

    // Check for how many tokens the user has staked/vaulted
    for (final addr in vault.keys) {
      final vaultValue = vault[addr];

      if (vaultValue == null) {
        // unreachable code: addr is a key of vault; just to have non-null types
        throw Exception('The key $addr does not exist on vault');
      }

      if (vaultValue.isEmpty) continue;

      final vaultBalance =
          vaultValue.map((a) => a.balance).reduce((a, b) => a + b);

      total += vaultBalance;

      if (balances[addr] != null) {
        balances.update(addr, (value) => value + vaultBalance);
      } else {
        balances.update(
          addr,
          (value) => vaultBalance,
          ifAbsent: () => vaultBalance,
        );
      }
    }

    // Create a weighted list of token holders
    final Map<ArweaveAddress, double> weighted = {};
    for (final addr in balances.keys) {
      weighted[addr] = balances[addr]! / total;
    }

    // Get a random holder based off of the weighted list of holders
    final randomHolder = weightedRandom(weighted, testingRandom: testingRandom);

    if (randomHolder == null) {
      throw CouldNotDetermineTokenHolder();
    }

    return randomHolder;
  }

  Future<CommunityContractData> _getCommunityContractData() async {
    final currentTime = DateTime.now();

    if (_communityContractData != null &&
        _lastFetchedTime != null &&
        currentTime.difference(_lastFetchedTime!).inMinutes < 30) {
      return _communityContractData!;
    }

    _communityContractData = await _contractOracle.getCommunityContract();
    _lastFetchedTime = currentTime;

    return _communityContractData!;
  }
}

class CouldNotDetermineTokenHolder extends Equatable implements Exception {
  final String _errMessage =
      'Token holder target could not be determined for community tip distribution';

  @override
  String toString() {
    return _errMessage;
  }

  @override
  List<Object?> get props => [];
}
