import 'dart:math';

import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:equatable/equatable.dart';
import 'package:pst/pst.dart';
import 'package:pst/src/implementations/token_holder_selector.dart';

/// Minimum ArDrive community tip from the Community Improvement Proposal Doc:
/// https://arweave.net/Yop13NrLwqlm36P_FDCdMaTBwSlj0sdNGAC4FqfRUgo
final minArDriveCommunityWinstonTip = Winston(BigInt.from(10000000));

// TODO: implement unit tests
class CommunityOracle {
  final ContractOracle _contractOracle;
  final TokenHolderSelector _tokenHolderSelector;
  CommunityContractData? _communityContractData;
  DateTime? _lastFetchedTime;

  CommunityOracle(
    ContractOracle contractOracle,
    TokenHolderSelector tokenHolderSelector,
  )   : _contractOracle = contractOracle,
        _tokenHolderSelector = tokenHolderSelector;

  Future<Winston> getCommunityWinstonTip(Winston winstonCost) async {
    final contractData = await _getCommunityContractData();

    final CommunityTipPercentage tipPercentage =
        contractData.settings.fee / 100.0;

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
    return _tokenHolderSelector.selectTokenHolder(testingRandom: testingRandom);
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
