import 'package:ardrive/blocs/upload/limits.dart';
import 'package:ardrive/blocs/upload/upload_handles/bundle_upload_handle.dart';
import 'package:ardrive/blocs/upload/upload_handles/folder_data_item_upload_handle.dart';
import 'package:ardrive/blocs/upload/upload_handles/upload_handle.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/bundles/first_fit_decreasing_bundle_packer.dart';
import 'package:ardrive/utils/logger.dart';

import '../upload_handles/file_data_item_upload_handle.dart';
import '../upload_handles/file_v2_upload_handle.dart';

class UploadPlan {
  /// A map of [FileV2UploadHandle]s keyed by their respective file's id.
  late Map<String, FileV2UploadHandle> fileV2UploadHandles;

  final List<BundleUploadHandle> bundleUploadHandles = [];

  final int maxDataItemCount;

  UploadPlan._create({
    required this.fileV2UploadHandles,
    required this.maxDataItemCount,
  });

  static Future<UploadPlan> create({
    required Map<String, FileV2UploadHandle> fileV2UploadHandles,
    required Map<String, FileDataItemUploadHandle> fileDataItemUploadHandles,
    required Map<String, FolderDataItemUploadHandle>
        folderDataItemUploadHandles,
    required TurboUploadService turboUploadService,
    required int maxDataItemCount,
    required bool useTurbo,
  }) async {
    final uploadPlan = UploadPlan._create(
      fileV2UploadHandles: fileV2UploadHandles,
      maxDataItemCount: maxDataItemCount,
    );

    if (fileDataItemUploadHandles.isNotEmpty ||
        folderDataItemUploadHandles.isNotEmpty) {
      await uploadPlan.createBundleHandlesFromDataItemHandles(
        fileDataItemUploadHandles: fileDataItemUploadHandles,
        folderDataItemUploadHandles: folderDataItemUploadHandles,
        turboUploadService: turboUploadService,
        maxDataItemCount: maxDataItemCount,
        useTurbo: useTurbo,
      );
    }

    return uploadPlan;
  }

  Future<void> createBundleHandlesFromDataItemHandles({
    required bool useTurbo,
    Map<String, FileDataItemUploadHandle> fileDataItemUploadHandles = const {},
    Map<String, FolderDataItemUploadHandle> folderDataItemUploadHandles =
        const {},
    required TurboUploadService turboUploadService,
    required int maxDataItemCount,
  }) async {
    logger.i(
        'Creating bundle handles using First-Fit-Decreasing algorithm with max $maxDataItemCount files per bundle');
    final int maxBundleSize = getBundleSizeLimit(useTurbo);

    // Use First-Fit-Decreasing packer for optimal space utilization
    // This sorts items by size and packs them efficiently, reducing total bundle count by ~10-20%
    final folderItems = await FirstFitDecreasingBundlePacker<UploadHandle>(
      maxBundleSize: maxBundleSize,
      maxDataItemCount: maxDataItemCount,
    ).packItems([...folderDataItemUploadHandles.values]);

    final fileItems = await FirstFitDecreasingBundlePacker<UploadHandle>(
      maxBundleSize: maxBundleSize,
      maxDataItemCount: maxDataItemCount,
    ).packItems([
      ...fileDataItemUploadHandles.values,
    ]);

    final bundleItems = [...folderItems, ...fileItems];

    for (var uploadHandles in bundleItems) {
      final bundleToUpload = await BundleUploadHandle.create(
        fileDataItemUploadHandles: List.from(
          uploadHandles.whereType<FileDataItemUploadHandle>(),
        ),
        folderDataItemUploadHandles: List.from(
          uploadHandles.whereType<FolderDataItemUploadHandle>(),
        ),
      );
      bundleUploadHandles.add(bundleToUpload);
      uploadHandles.clear();
    }
    fileDataItemUploadHandles.clear();
  }
}
