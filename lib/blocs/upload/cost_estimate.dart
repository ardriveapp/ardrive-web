import 'package:ardrive/blocs/upload/models/upload_plan.dart';
import 'package:ardrive/blocs/upload/upload_handles/bundle_upload_handle.dart';
import 'package:ardrive/blocs/upload/upload_handles/file_v2_upload_handle.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/pst/pst.dart';
import 'package:ardrive/types/winston.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';

class CostEstimate {
  /// The cost to upload the data, in AR.
  final String arUploadCost;

  /// The cost to upload the data, in USD.
  ///
  /// Null if conversion rate could not be retrieved.
  final double? usdUploadCost;

  /// The fee amount provided to PST holders.
  final BigInt pstFee;

  /// The sum of the upload cost and fees.
  final BigInt totalCost;

  CostEstimate._create({
    required this.arUploadCost,
    required this.pstFee,
    required this.totalCost,
    this.usdUploadCost,
  });

  static Future<CostEstimate> create({
    required UploadPlan uploadPlan,
    required ArweaveService arweaveService,
    required PstService pstService,
    required Wallet wallet,
  }) async {
    final v2FileUploadHandles = uploadPlan.fileV2UploadHandles;

    final dataItemsCost = await estimateCostOfAllBundles(
      bundleUploadHandles: uploadPlan.bundleUploadHandles,
      arweaveService: arweaveService,
    );
    final v2FilesUploadCost = await estimateV2UploadsCost(
        fileUploadHandles: v2FileUploadHandles.values.toList(),
        arweaveService: arweaveService);

    final bundlePstFee = await pstService.getPSTFee(dataItemsCost);
    final v2FilesPstFee = v2FilesUploadCost <= BigInt.zero
        ? Winston(BigInt.zero)
        : await pstService.getPSTFee(v2FilesUploadCost);

    final totalCost = v2FilesUploadCost +
        dataItemsCost +
        bundlePstFee.value +
        v2FilesPstFee.value;

    final arUploadCost = winstonToAr(totalCost);
    final usdUploadCost = await arweaveService
        .getArUsdConversionRate()
        .then((conversionRate) => double.parse(arUploadCost) * conversionRate);

    return CostEstimate._create(
      totalCost: totalCost,
      arUploadCost: arUploadCost,
      pstFee: v2FilesPstFee.value + bundlePstFee.value,
      usdUploadCost: usdUploadCost,
    );
  }

  static Future<BigInt> estimateCostOfAllBundles({
    required List<BundleUploadHandle> bundleUploadHandles,
    required ArweaveService arweaveService,
  }) async {
    var totalCost = BigInt.zero;
    for (var bundle in bundleUploadHandles) {
      totalCost += await estimateBundleUploadCost(
        bundle: bundle,
        arweave: arweaveService,
      );
    }
    return totalCost;
  }

  static Future<BigInt> estimateBundleUploadCost({
    required BundleUploadHandle bundle,
    required ArweaveService arweave,
  }) async {
    return arweave.getPrice(byteSize: await bundle.computeBundleSize());
  }

  static Future<BigInt> estimateV2UploadsCost({
    required List<FileV2UploadHandle> fileUploadHandles,
    required ArweaveService arweaveService,
  }) async {
    var totalCost = BigInt.zero;
    for (final cost in fileUploadHandles.map((e) async =>
        await estimateV2FileUploadCost(
            fileUploadHandle: e, arweaveService: arweaveService))) {
      totalCost += await cost;
    }
    return totalCost;
  }

  static Future<BigInt> estimateV2FileUploadCost({
    required FileV2UploadHandle fileUploadHandle,
    required ArweaveService arweaveService,
  }) async {
    return await arweaveService.getPrice(
            byteSize: fileUploadHandle.getFileDataSize()) +
        await arweaveService.getPrice(
            byteSize: fileUploadHandle.getMetadataJSONSize());
  }
}
