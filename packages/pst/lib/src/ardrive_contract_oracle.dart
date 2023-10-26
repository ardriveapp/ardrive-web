import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:pst/src/contract_oracle.dart';
import 'package:pst/src/pst_contract_data.dart';
import 'package:retry/retry.dart';

const _maxReadContractAttempts = 3;

class ArDriveContractOracle implements ContractOracle {
  final List<ContractOracle> _contractOracles;
  final ContractOracle? _fallbackContractOracle;

  ArDriveContractOracle(
    List<ContractOracle> contractOracles, {
    ContractOracle? fallbackContractOracle,
  })  : _fallbackContractOracle = fallbackContractOracle,
        _contractOracles = contractOracles {
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
    try {
      final contract = await getFirstFutureResult<CommunityContractData>(
          _contractOracles
              .map((e) async => await _getContractWithRetries(e))
              .toList());

      return contract;
    } catch (e) {
      debugPrint('Could not read contract state from any of the oracles');
      if (_fallbackContractOracle == null) {
        throw const CouldNotReadContractState(
          reason: 'No fallback contract reader provided',
        );
      }

      return _getContractWithRetries(_fallbackContractOracle!);
    }
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
