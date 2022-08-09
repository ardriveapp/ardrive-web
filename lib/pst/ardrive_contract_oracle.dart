import 'package:ardrive/pst/contract_oracle.dart';
import 'package:ardrive/pst/pst_contract_data.dart';

const maxReadContractAttempts = 3;

class ArDriveContractOracle implements ContractOracle {
  final List<ContractOracle> _contractOracles;

  ArDriveContractOracle(List<ContractOracle> contractOracles)
      : _contractOracles = contractOracles {
    if (contractOracles.isEmpty) {
      throw EmptyContractOracles();
    }
  }

  @override
  Future<CommunityContractData> getCommunityContract() async {
    int readContractAttempts = 0;
    int contractOracleIndex = 0;
    CommunityContractData? data;

    while (data == null && _contractOracles.length < contractOracleIndex) {
      final contractOracle = _contractOracles[contractOracleIndex];
      readContractAttempts = 0;

      while (data == null && readContractAttempts < maxReadContractAttempts) {
        try {
          data = await contractOracle.getCommunityContract();
        } catch (_) {
          readContractAttempts++;
        }
      }

      contractOracleIndex++;
    }

    if (data == null) {
      throw const CouldNotReadContractState(
        reason: 'Max retry attempts reached',
      );
    }

    return data;
  }

  @override
  Future<CommunityTipPercentage> getTipPercentageFromContract() async {
    final contractState = await getCommunityContract();
    return contractState.settings.fee / 100;
  }
}

class EmptyContractOracles implements Exception {
  @override
  String toString() {
    return 'Expected at least one contract reader';
  }
}

class CouldNotReadContractState implements Exception {
  final String _errMessage = 'Expected at least one contract reader';
  final String? _reason;

  const CouldNotReadContractState({String? reason}) : _reason = reason;

  @override
  String toString() {
    return _reason != null ? '$_errMessage. $_reason' : _errMessage;
  }
}
