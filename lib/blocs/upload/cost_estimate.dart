import 'package:ardrive/blocs/upload/models/upload_plan.dart';
import 'package:ardrive/blocs/upload/upload_handles/bundle_upload_handle.dart';
import 'package:ardrive/blocs/upload/upload_handles/file_v2_upload_handle.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/pst/pst.dart';
import 'package:ardrive/turbo/turbo.dart';
import 'package:ardrive/types/winston.dart';
import 'package:ardrive/utils/ar_cost_to_usd.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';

abstract class ArDriveUploadCostCalculator {
  Future<UploadCostEstimate> calculateCost({
    required Map<String, FileV2UploadHandle> fileV2UploadHandles,
    required List<BundleUploadHandle> bundleUploadHandles,
  });

  Future<int> getSizeOfAllBundles(
      List<BundleUploadHandle> bundleUploadHandles) async {
    var totalSize = 0;

    for (var bundle in bundleUploadHandles) {
      totalSize += await bundle.computeBundleSize();
    }
    return totalSize;
  }

  Future<int> getSizeOfAllV2Files(
      Map<String, FileV2UploadHandle> fileV2UploadHandles) async {
    var totalSize = 0;

    for (var file in fileV2UploadHandles.values) {
      totalSize += file.getFileDataSize();
      totalSize += file.getMetadataJSONSize();
    }
    return totalSize;
  }
}

class UploadCostEstimate {
  final double? usdUploadCost;

  /// The fee amount provided to PST holders.
  final BigInt pstFee;

  /// The sum of the upload cost and fees.
  final BigInt totalCost;

  final int totalSize;

  UploadCostEstimate({
    required this.pstFee,
    required this.totalCost,
    required this.totalSize,
    required this.usdUploadCost,
  });
}

class UploadCostEstimateCalculatorForAR extends ArDriveUploadCostCalculator {
  final ArweaveService _arweaveService;
  final PstService _pstService;

  UploadCostEstimateCalculatorForAR({
    required ArweaveService arweaveService,
    required PstService pstService,
  })  : _arweaveService = arweaveService,
        _pstService = pstService;

  @override
  Future<UploadCostEstimate> calculateCost({
    required Map<String, FileV2UploadHandle> fileV2UploadHandles,
    required List<BundleUploadHandle> bundleUploadHandles,
  }) async {
    final bundleSizes = await getSizeOfAllBundles(bundleUploadHandles);
    final v2FileSizes = await getSizeOfAllV2Files(fileV2UploadHandles);

    final dataItemsCostInAR =
        await _arweaveService.getPrice(byteSize: bundleSizes);
    final v2FilesUploadCostInAR =
        await _arweaveService.getPrice(byteSize: v2FileSizes);

    final bundlePstFeeAR = await _pstService.getPSTFee(dataItemsCostInAR);
    final v2FilesPstFeeAR = await _pstService.getPSTFee(v2FilesUploadCostInAR);

    final totalCostAR = dataItemsCostInAR +
        v2FilesUploadCostInAR +
        bundlePstFeeAR.value +
        v2FilesPstFeeAR.value;

    final arUploadCost = winstonToAr(totalCostAR);

    final usdUploadCost = await arCostToUsdOrNull(
      _arweaveService,
      double.parse(arUploadCost),
    );

    return UploadCostEstimate(
      pstFee: bundlePstFeeAR.value + v2FilesPstFeeAR.value,
      totalCost: totalCostAR,
      totalSize: bundleSizes + v2FileSizes,
      usdUploadCost: usdUploadCost,
    );
  }
}

class TurboUploadCostCalculator extends ArDriveUploadCostCalculator {
  final TurboCostCalculator _turboCostCalculator;
  final TurboPriceEstimator _priceEstimator;
  final PstService _pstService;

  TurboUploadCostCalculator({
    required TurboCostCalculator turboCostCalculator,
    required TurboPriceEstimator priceEstimator,
    required PstService pstService,
  })  : _turboCostCalculator = turboCostCalculator,
        _priceEstimator = priceEstimator,
        _pstService = pstService;

  @override
  Future<UploadCostEstimate> calculateCost({
    required Map<String, FileV2UploadHandle> fileV2UploadHandles,
    required List<BundleUploadHandle> bundleUploadHandles,
  }) async {
    final bundleSizes = await getSizeOfAllBundles(bundleUploadHandles);
    final v2FileSizes = await getSizeOfAllV2Files(fileV2UploadHandles);

    final dataItemCostInCredits =
        await _turboCostCalculator.getCostForBytes(byteSize: bundleSizes);
    final v2FilesUploadCostInCredits =
        await _turboCostCalculator.getCostForBytes(byteSize: v2FileSizes);

    final bundlePstFeeCredits =
        await _pstService.getPSTFee(dataItemCostInCredits);
    final v2FilesPstFeeCredits =
        await _pstService.getPSTFee(v2FilesUploadCostInCredits);

    final totalCostCredits = dataItemCostInCredits +
        v2FilesUploadCostInCredits +
        bundlePstFeeCredits.value +
        v2FilesPstFeeCredits.value;

    final usdUploadCostForARWithTurbo =
        await _priceEstimator.convertCreditsForUSD(
      credits: totalCostCredits,
    );

    logger.d('usdUploadCostForARWithTurbo: $usdUploadCostForARWithTurbo');

    return UploadCostEstimate(
      pstFee: bundlePstFeeCredits.value + v2FilesPstFeeCredits.value,
      totalCost: totalCostCredits,
      totalSize: bundleSizes + v2FileSizes,
      usdUploadCost: usdUploadCostForARWithTurbo,
    );
  }
}
