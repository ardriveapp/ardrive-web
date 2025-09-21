import 'package:ardrive_uploader/src/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';
// ignore: depend_on_referenced_packages
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
  final Arweave _arweave;
  final PstService _pstService;
  final ConvertArToUSD _arCostToUsd;

  UploadCostEstimateCalculatorForAR({
    required Arweave arweaveService,
    required PstService pstService,
    required ConvertArToUSD arCostToUsd,
  })  : _arweave = arweaveService,
        _arCostToUsd = arCostToUsd,
        _pstService = pstService;

  @override
  Future<UploadCostEstimate> calculateCost({
    required int totalSize,
  }) async {
    final costInAR = await _arweave.api
        .get('price/$totalSize')
        .then((res) => BigInt.parse(res.body));

    late final Winston pstFee;

    try {
      pstFee = await _pstService.getPSTFee(costInAR);
    } catch (e) {
      logger.e('Error adding community tip to transaction. Proceeding.', e);
      pstFee = Winston(BigInt.zero);
    }

    final totalCostAR = costInAR + pstFee.value;

    final arUploadCost = winstonToAr(totalCostAR);

    logger.d('Upload cost in AR: $arUploadCost');

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

abstract class ConvertForUSD<T> {
  Future<double?> convertForUSD(T value);
}

class ConvertArToUSD implements ConvertForUSD<double> {
  @override
  Future<double?> convertForUSD(
    double arCost,
  ) async {
    final arUsdConversionRate = await getArUsdConversionRateOrNull();

    if (arUsdConversionRate == null) {
      return null;
    }

    return arCost * arUsdConversionRate;
  }
}
