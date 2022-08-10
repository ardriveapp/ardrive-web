import 'dart:math';

import 'package:ardrive/pst/contract_oracle.dart';
import 'package:ardrive/pst/utils.dart';
import 'package:ardrive/types/winston.dart';

import '../types/arweave_address.dart';

/// Minimum ArDrive community tip from the Community Improvement Proposal Doc:
/// https://arweave.net/Yop13NrLwqlm36P_FDCdMaTBwSlj0sdNGAC4FqfRUgo
final minArDriveCommunityWinstonTip = Winston(BigInt.from(10000000));

class CommunityOracle {
  final ContractOracle _contractOracle;

  CommunityOracle(ContractOracle contractOracle)
      : _contractOracle = contractOracle;

  Future<Winston> getCommunityWinstonTip(Winston winstonCost) async {
    final tipPercentage = await _contractOracle.getTipPercentageFromContract();
    final value = max<int>(
      (winstonCost.value.toInt() * tipPercentage).floor(),
      minArDriveCommunityWinstonTip.value.toInt(),
    );
    return Winston(BigInt.from(value));
  }

  Future<ArweaveAddress> selectTokenHolder() async {
    final contract = await _contractOracle.getCommunityContract();
    final Map<ArweaveAddress, int> balances = Map.from(contract.balances);
    final vault = contract.vault;

    // Get the total number of token holders
    int total = 0;
    for (final addr in balances.keys) {
      total += balances[addr]!;
    }

    // Check for how many tokens the user has staked/vaulted
    for (final addr in vault.keys) {
      if (vault[addr]!.isEmpty) continue;

      final vaultBalance =
          vault[addr]!.map((a) => a.balance).reduce((a, b) => a + b);

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
    final randomHolder = weightedRandom(weighted);

    if (randomHolder == null) {
      throw CouldNotDetermineTokenHolder();
    }

    return randomHolder;
  }
}

class CouldNotDetermineTokenHolder implements Exception {
  final String _errMessage =
      'Token holder target could not be determined for community tip distribution';

  @override
  String toString() {
    return _errMessage;
  }
}
