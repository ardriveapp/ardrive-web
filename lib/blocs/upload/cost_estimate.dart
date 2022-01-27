import 'package:ardrive/blocs/upload/mapped_upload_handles.dart';
import 'package:ardrive/entities/entity.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/pst/pst.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';
import 'package:package_info_plus/package_info_plus.dart';

final minimumPstTip = BigInt.from(10000000);

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

  /// The [Transaction] that pays `pstFee` to a random PST holder. (Only for v2 transaction uploads)
  final Transaction? v2FilesFeeTx;

  CostEstimate._create({
    required this.arUploadCost,
    required this.pstFee,
    required this.totalCost,
    this.usdUploadCost,
    this.v2FilesFeeTx,
  });

  static Future<CostEstimate> create({
    required MappedUploadHandles mappedUploadHandles,
    required ArweaveService arweaveService,
    required PstService pstService,
    required Wallet wallet,
  }) async {
    final _v2FileUploadHandles = mappedUploadHandles.v2FileUploadHandles;
    final dataItemsCost = mappedUploadHandles.bundleUploadHandles.isNotEmpty
        ? await mappedUploadHandles.estimateCostOfAllBundles(
            arweaveService: arweaveService,
          )
        : BigInt.zero;
    var v2FilesUploadCost = BigInt.zero;
    for (final value in _v2FileUploadHandles.values.map((e) async =>
        await e.estimateUploadCost(arweaveService: arweaveService))) {
      v2FilesUploadCost += await value;
    }

    final bundlePstFee = await pstService.getPSTFee(dataItemsCost);

    Transaction? v2FilesFeeTx;
    if (_v2FileUploadHandles.isNotEmpty) {
      v2FilesFeeTx = await prepareAndSignV2FilesTipTx(
        arweaveService: arweaveService,
        pstService: pstService,
        wallet: wallet,
        v2FilesUploadCost: v2FilesUploadCost,
      );
    }
    final v2FilesPstFee = (v2FilesFeeTx?.quantity ?? BigInt.zero);
    final totalCost =
        v2FilesUploadCost + dataItemsCost + bundlePstFee + v2FilesPstFee;

    final arUploadCost = winstonToAr(totalCost);
    final usdUploadCost = await arweaveService
        .getArUsdConversionRate()
        .then((conversionRate) => double.parse(arUploadCost) * conversionRate);
    return CostEstimate._create(
      totalCost: totalCost,
      arUploadCost: arUploadCost,
      pstFee: v2FilesPstFee + bundlePstFee,
      usdUploadCost: usdUploadCost,
      v2FilesFeeTx: v2FilesFeeTx,
    );
  }

  static Future<Transaction?> prepareAndSignV2FilesTipTx({
    required ArweaveService arweaveService,
    required PstService pstService,
    required Wallet wallet,
    required v2FilesUploadCost,
  }) async {
    if (v2FilesUploadCost <= BigInt.zero) {
      return null;
    }
    final packageInfo = await PackageInfo.fromPlatform();
    final pstFee = await pstService.getPSTFee(v2FilesUploadCost);
    final quantity = pstFee > minimumPstTip ? pstFee : minimumPstTip;

    final feeTx = await arweaveService.client.transactions.prepare(
      Transaction(
        target: await pstService.getWeightedPstHolder(),
        quantity: quantity,
      ),
      wallet,
    )
      ..addApplicationTags(version: packageInfo.version)
      ..addTag('Type', 'fee')
      ..addTag(TipType.tagName, TipType.dataUpload);
    await feeTx.sign(wallet);
    return feeTx;
  }
}
