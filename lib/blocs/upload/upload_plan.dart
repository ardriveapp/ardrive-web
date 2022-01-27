import 'package:ardrive/blocs/upload/bundle_upload_handle.dart';
import 'package:ardrive/utils/bundles/next_fit_bundle_packer.dart';

import 'data_item_upload_handle.dart';
import 'file_upload_handle.dart';

final bundleSizeLimit = 503316480;
final maxBundleDataItemCount = 500;
final maxFilesPerBundle = maxBundleDataItemCount ~/ 2;

class UploadPlan {
  /// A map of [FileUploadHandle]s keyed by their respective file's id.
  late Map<String, FileUploadHandle> v2FileUploadHandles;

  final List<BundleUploadHandle> bundleUploadHandles = [];

  UploadPlan._create({
    required this.v2FileUploadHandles,
  });

  static Future<UploadPlan> create({
    required Map<String, FileUploadHandle> v2FileUploadHandles,
    required Map<String, DataItemUploadHandle> dataItemUploadHandles,
  }) async {
    final bundle = UploadPlan._create(
      v2FileUploadHandles: v2FileUploadHandles,
    );
    await bundle.createBundleHandlesFromDataItemHandles(dataItemUploadHandles);
    return bundle;
  }

  Future<void> createBundleHandlesFromDataItemHandles(
      Map<String, DataItemUploadHandle> dataItemUploadHandles) async {
    // NOTE: Using maxFilesPerBundle since FileUploadHandles have 2 data items
    final bundleItems = await NextFitBundlePacker<DataItemUploadHandle>(
      maxBundleSize: bundleSizeLimit,
      maxDataItemCount: maxFilesPerBundle,
    ).packItems(dataItemUploadHandles.values.toList());
    for (var uploadHandles in bundleItems) {
      final bundleToUpload = await BundleUploadHandle.create(
        dataItemUploadHandles: List.from(uploadHandles),
      );
      bundleUploadHandles.add(bundleToUpload);
      uploadHandles.clear();
    }
    dataItemUploadHandles.clear();
  }
}
