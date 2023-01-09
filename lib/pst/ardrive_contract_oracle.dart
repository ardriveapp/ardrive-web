import 'package:ardrive/pst/contract_oracle.dart';
import 'package:ardrive/pst/pst_contract_data.dart';
import 'package:ardrive/utils/first_future_with_a_value.dart';
import 'package:equatable/equatable.dart';
import 'package:retry/retry.dart';

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
    try {
      CommunityContractData data = await _getContractFromOracles();

      return data;
    } catch (e) {
      throw const CouldNotReadContractState(
        reason: 'Max retry attempts reached',
      );
    }
  }

  /// iterates over all contract readers attempting to read the contract
  Future<CommunityContractData> _getContractFromOracles() async {
    final contract = await firstWithAValue<CommunityContractData>(
        _contractOracles
            .map((e) async => await _getContractWithRetries(e))
            .toList());

    return contract;
  }

  /// attempts multiple retries to read the given contract oracle
  Future<CommunityContractData> _getContractWithRetries(
    ContractOracle contractOracle, {
    int maxAttempts = _maxReadContractAttempts,
  }) async {
    try {
      final data = await retry(
        contractOracle.getCommunityContract,
        maxAttempts: maxAttempts,
      );
      return data;
    } catch (_) {
      rethrow;
    }
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
