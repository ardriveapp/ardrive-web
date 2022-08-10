import 'package:ardrive/pst/contract_oracle.dart';
import 'package:ardrive/pst/pst_contract_data.dart';
import 'package:equatable/equatable.dart';

const _maxReadContractAttempts = 3;

class ArDriveContractOracle implements ContractOracle {
  final List<ContractOracle> _contractOracles;

  ArDriveContractOracle(List<ContractOracle> contractOracles)
      : _contractOracles = contractOracles {
    if (contractOracles.isEmpty) {
      throw const EmptyContractOracles();
    }
  }

  @override
  Future<CommunityContractData> getCommunityContract() async {
    CommunityContractData? data = await _getContractFromOracles();

    if (data == null) {
      throw const CouldNotReadContractState(
        reason: 'Max retry attempts reached',
      );
    }

    return data;
  }

  /// iterates over all contract readers attempting to read the contract
  Future<CommunityContractData?> _getContractFromOracles() async {
    int contractOracleIndex = 0;
    CommunityContractData? data;

    while (data == null && _contractOracles.length > contractOracleIndex) {
      final contractOracle = _contractOracles[contractOracleIndex];
      data = await _getContractWithRetries(contractOracle);
      contractOracleIndex++;
    }

    return data;
  }

  /// attempts multiple retries to read the given contract oracle
  Future<CommunityContractData?> _getContractWithRetries(
    ContractOracle contractOracle, {
    int maxAttempts = _maxReadContractAttempts,
  }) async {
    CommunityContractData? data;
    int readContractAttempts = 0;

    while (data == null && readContractAttempts < maxAttempts) {
      try {
        data = await contractOracle.getCommunityContract();
      } catch (_) {
        readContractAttempts++;
      }
    }

    return data;
  }

  @override
  Future<CommunityTipPercentage> getTipPercentageFromContract() async {
    final contractState = await getCommunityContract();
    return contractState.settings.fee / 100;
  }
}

class EmptyContractOracles extends Equatable implements Exception {
  const EmptyContractOracles();

  @override
  String toString() {
    return 'Expected at least one contract reader';
  }

  @override
  List<Object?> get props => [];
}

class CouldNotReadContractState extends Equatable implements Exception {
  final String _errMessage = 'Could not read contract state';
  final String? _reason;

  const CouldNotReadContractState({String? reason}) : _reason = reason;

  @override
  String toString() {
    return _reason != null ? '$_errMessage. $_reason' : _errMessage;
  }

  @override
  List<Object?> get props => [_reason];
}
