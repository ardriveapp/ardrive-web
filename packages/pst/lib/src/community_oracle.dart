import 'dart:math';

import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:equatable/equatable.dart';
import 'package:pst/pst.dart';
import 'package:pst/src/utils.dart';

/// Minimum ArDrive community tip from the Community Improvement Proposal Doc:
/// https://arweave.net/Yop13NrLwqlm36P_FDCdMaTBwSlj0sdNGAC4FqfRUgo
final minArDriveCommunityWinstonTip = Winston(BigInt.from(10000000));

// TODO: implement unit tests
class CommunityOracle {
  final ContractOracle _contractOracle;
  CommunityContractData? _communityContractData;
  DateTime? _lastFetchedTime;

  CommunityOracle(ContractOracle contractOracle)
      : _contractOracle = contractOracle;

  Future<Winston> getCommunityWinstonTip(Winston winstonCost) async {
    final contractData = await _getCommunityContractData();

    final CommunityTipPercentage tipPercentage =
        contractData.settings.fee / 100;

    final value = max<int>(
      // Workaround [BigInt] percentage division problems
      // by first multiplying by the percentage * 100 and then dividing by 100.
      (winstonCost.value * BigInt.from(tipPercentage * 100) ~/ BigInt.from(100))
          .toInt(),
      minArDriveCommunityWinstonTip.value.toInt(),
    );

    return Winston(BigInt.from(value));
  }

  Future<ArweaveAddress> selectTokenHolder({
    double? testingRandom, // for testing purposes only
  }) async {
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
