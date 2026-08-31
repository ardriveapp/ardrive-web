import 'dart:async';

import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/utils.dart';
import 'package:equatable/equatable.dart';
import 'package:pst/pst.dart';

abstract class ArDriveUploadCostCalculator {
  Future<UploadCostEstimate> calculateCost({required int totalSize});
}

class UploadCostEstimate extends Equatable {
  final double? usdUploadCost;

  /// The fee amount provided to PST holders.
  final BigInt pstFee;

  /// The sum of the upload cost and fees.
  final BigInt totalCost;

  final int totalSize;

  const UploadCostEstimate({
    required this.pstFee,
    required this.totalCost,
    required this.totalSize,
    required this.usdUploadCost,
  });

  factory UploadCostEstimate.zero() {
    return UploadCostEstimate(
      pstFee: BigInt.zero,
      totalCost: BigInt.zero,
      totalSize: 0,
      usdUploadCost: 0,
    );
  }

  @override
  List<Object?> get props => [
        usdUploadCost,
        pstFee,
        totalCost,
        totalSize,
      ];
}

class UploadCostEstimateCalculatorForAR extends ArDriveUploadCostCalculator {
  /// How long to wait for the community tip before giving up on it.
  ///
  /// The fee is already optional - the `catch` below proceeds without it - so
  /// this only decides how long "optional" is allowed to block a price the
  /// user is waiting on.
  static const kPstFeeTimeout = Duration(seconds: 6);

  final ArweaveService _arweaveService;
  final PstService _pstService;
  final ConvertArToUSD _arCostToUsd;
  final Duration _pstFeeTimeout;

  UploadCostEstimateCalculatorForAR({
    required ArweaveService arweaveService,
    required PstService pstService,
    required ConvertArToUSD arCostToUsd,
    Duration pstFeeTimeout = kPstFeeTimeout,
  })  : _arweaveService = arweaveService,
        _arCostToUsd = arCostToUsd,
        _pstService = pstService,
        _pstFeeTimeout = pstFeeTimeout;

  @override
  Future<UploadCostEstimate> calculateCost({
    required int totalSize,
  }) async {
    final costInAR = await _arweaveService.getPrice(byteSize: totalSize);

    Winston pstFee = Winston(BigInt.zero);
    try {
      pstFee = await _pstService.getPSTFee(costInAR).timeout(_pstFeeTimeout);
    } on TimeoutException {
      // The same outcome as the `catch` below, for the case that `catch` never
      // sees. Reading the community contract goes through a chain of oracles
      // and retries, none of which has a deadline, so a request that hangs
      // rather than fails hangs this call for ever - and the fee is already
      // treated as optional here, so waiting for it indefinitely buys nothing.
      logger.e(
        'The community tip could not be read within '
        '${_pstFeeTimeout.inSeconds}s. Proceeding without it.',
      );
    } catch (e) {
      logger.e('Error adding community tip to transaction. Proceeding.', e);
    }

    final totalCostAR = costInAR + pstFee.value;

    final arUploadCost = winstonToAr(totalCostAR);

    logger.i('Upload cost in AR: $arUploadCost');

    final usdUploadCost = await _arCostToUsd.convertForUSD(
      double.parse(arUploadCost),
    );

    return UploadCostEstimate(
      pstFee: pstFee.value,
      totalCost: totalCostAR,
      totalSize: totalSize,
      usdUploadCost: usdUploadCost,
    );
  }
}

class TurboUploadCostCalculator extends ArDriveUploadCostCalculator {
  final TurboCostCalculator _turboCostCalculator;
  final TurboPriceEstimator _priceEstimator;

  TurboUploadCostCalculator({
    required TurboCostCalculator turboCostCalculator,
    required TurboPriceEstimator priceEstimator,
  })  : _turboCostCalculator = turboCostCalculator,
        _priceEstimator = priceEstimator;

  @override
  Future<UploadCostEstimate> calculateCost({
    required int totalSize,
  }) async {
    final cost =
        await _turboCostCalculator.getCostForBytes(byteSize: totalSize);

    final totalCostCredits = cost;

    final usdUploadCostForARWithTurbo = await _priceEstimator.convertForUSD(
      totalCostCredits,
    );

    return UploadCostEstimate(
      pstFee: BigInt.zero,
      totalCost: totalCostCredits,
      totalSize: totalSize,
      usdUploadCost: usdUploadCostForARWithTurbo,
    );
  }
}

abstract class ConvertForUSD<T> {
  Future<double?> convertForUSD(T value);
}

class ConvertArToUSD implements ConvertForUSD<double> {
  final ArweaveService arweave;

  ConvertArToUSD({required this.arweave});

  @override
  Future<double?> convertForUSD(
    double arCost,
  ) async {
    final arUsdConversionRate = await arweave.getArUsdConversionRateOrNull();

    if (arUsdConversionRate == null) {
      return null;
    }

    return arCost * arUsdConversionRate;
  }
}
