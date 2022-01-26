import 'package:ardrive/blocs/upload/bundle_upload_handle.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/utils/bundles/next_fit_bundle_packer.dart';

import 'data_item_upload_handle.dart';
import 'file_upload_handle.dart';

final bundleSizeLimit = 503316480;
final maxBundleDataItemCount = 500;
final maxFilesPerBundle = maxBundleDataItemCount ~/ 2;

class MappedUploadHandles {
  /// A map of [FileUploadHandle]s keyed by their respective file's id.
  late Map<String, FileUploadHandle> v2FileUploadHandles;

  /// A map of [DataItemUploadHandle]s keyed by their respective file's id.
  late Map<String, DataItemUploadHandle> _dataItemUploadHandles;
  final List<BundleUploadHandle> bundleUploadHandles = [];

  MappedUploadHandles._create({
    required Map<String, DataItemUploadHandle> dataItemUploadHandles,
    required this.v2FileUploadHandles,
  }) {
    _dataItemUploadHandles = dataItemUploadHandles;
  }

  static Future<MappedUploadHandles> create({
    required Map<String, FileUploadHandle> v2FileUploadHandles,
    required Map<String, DataItemUploadHandle> dataItemUploadHandles,
  }) async {
    final bundle = MappedUploadHandles._create(
      dataItemUploadHandles: dataItemUploadHandles,
      v2FileUploadHandles: v2FileUploadHandles,
    );
    await bundle.prepareBundleHandles();
    return bundle;
  }

  Future<void> prepareBundleHandles() async {
    // NOTE: Using maxFilesPerBundle since FileUploadHandles have 2 data items
    final bundleItems = await NextFitBundlePacker<DataItemUploadHandle>(
      maxBundleSize: bundleSizeLimit,
      maxDataItemCount: maxFilesPerBundle,
    ).packItems(_dataItemUploadHandles.values.toList());
    for (var uploadHandles in bundleItems) {
      final bundleToUpload = await BundleUploadHandle.create(
        dataItemUploadHandles: List.from(uploadHandles),
      );
      bundleUploadHandles.add(bundleToUpload);
      uploadHandles.clear();
    }
    _dataItemUploadHandles.clear();
  }

  Future<BigInt> estimateBundleCosts({
    required ArweaveService arweaveService,
  }) async {
    var totalCost = BigInt.zero;
    for (var bundle in bundleUploadHandles) {
      totalCost += await bundle.estimateBundleCost(
        arweave: arweaveService,
      );
    }
    return totalCost;
  }
}
