import 'package:ardrive/blocs/upload/upload_handles/bundle_upload_handle.dart';
import 'package:ardrive/blocs/upload/upload_handles/folder_data_item_upload_handle.dart';
import 'package:ardrive/blocs/upload/upload_handles/upload_handle.dart';
import 'package:ardrive/utils/bundles/next_fit_bundle_packer.dart';
import 'package:ardrive/utils/constants.dart';
import 'package:flutter/foundation.dart';

import '../upload_handles/file_data_item_upload_handle.dart';
import '../upload_handles/file_v2_upload_handle.dart';

const bundleSizeLimit = 503316480; // 480MiB
const mobileBundleSizeLimit = 209715200; // 200MiB
const maxBundleDataItemCount = 500;
const maxFilesPerBundle = maxBundleDataItemCount ~/ 2;

class UploadPlan {
  /// A map of [FileV2UploadHandle]s keyed by their respective file's id.
  late Map<String, FileV2UploadHandle> fileV2UploadHandles;
  final List<BundleUploadHandle> bundleUploadHandles = [];

  // These are only used for turbo bundler uploads
  bool isFreeThanksToTurbo = false;
  final Map<String, FileDataItemUploadHandle> fileDataItemHandles = {};
  final Map<String, FolderDataItemUploadHandle> folderDataItemHandles = {};

  UploadPlan._create({
    required this.fileV2UploadHandles,
  });

  static Future<UploadPlan> create({
    required Map<String, FileV2UploadHandle> fileV2UploadHandles,
    required Map<String, FileDataItemUploadHandle> fileDataItemUploadHandles,
    required Map<String, FolderDataItemUploadHandle>
        folderDataItemUploadHandles,
  }) async {
    final uploadPlan = UploadPlan._create(
      fileV2UploadHandles: fileV2UploadHandles,
    );
    if (fileDataItemUploadHandles.isNotEmpty ||
        folderDataItemUploadHandles.isNotEmpty) {
      await uploadPlan.createBundleHandlesFromDataItemHandles(
        fileDataItemUploadHandles: fileDataItemUploadHandles,
        folderDataItemUploadHandles: folderDataItemUploadHandles,
      );
    }
    return uploadPlan;
  }

  Future<void> createBundleHandlesFromDataItemHandles({
    Map<String, FileDataItemUploadHandle> fileDataItemUploadHandles = const {},
    Map<String, FolderDataItemUploadHandle> folderDataItemUploadHandles =
        const {},
  }) async {
    isFreeThanksToTurbo = useTurbo &&
        fileDataItemUploadHandles.values
            .map((dataItem) => dataItem.size <= freeArfsDataAllowLimit)
            .reduce((value, acc) => value && acc);
    if (isFreeThanksToTurbo) {
      this.fileDataItemHandles.addAll(fileDataItemUploadHandles);
      this.folderDataItemHandles.addAll(folderDataItemUploadHandles);
      return;
    }
    // Set bundle size limit according the platform
    // This should be reviewed when we implement stream uploads
    const int maxBundleSize = kIsWeb ? bundleSizeLimit : mobileBundleSizeLimit;

    final bundleItems = await NextFitBundlePacker<UploadHandle>(
      maxBundleSize: maxBundleSize,
      maxDataItemCount: maxFilesPerBundle,
    ).packItems([
      ...fileDataItemUploadHandles.values,
      ...folderDataItemUploadHandles.values
    ]);
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
