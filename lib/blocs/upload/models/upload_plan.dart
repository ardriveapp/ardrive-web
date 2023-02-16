import 'package:ardrive/blocs/upload/upload_handles/bundle_upload_handle.dart';
import 'package:ardrive/blocs/upload/upload_handles/folder_data_item_upload_handle.dart';
import 'package:ardrive/blocs/upload/upload_handles/upload_handle.dart';
import 'package:ardrive/services/turbo/turbo.dart';
import 'package:ardrive/utils/bundles/next_fit_bundle_packer.dart';
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

  bool useTurbo = false;

  UploadPlan._create({
    required this.fileV2UploadHandles,
  });

  static Future<UploadPlan> create({
    required Map<String, FileV2UploadHandle> fileV2UploadHandles,
    required Map<String, FileDataItemUploadHandle> fileDataItemUploadHandles,
    required Map<String, FolderDataItemUploadHandle>
        folderDataItemUploadHandles,
    required TurboService turboService,
  }) async {
    final uploadPlan = UploadPlan._create(
      fileV2UploadHandles: fileV2UploadHandles,
    );
    if (fileDataItemUploadHandles.isNotEmpty ||
        folderDataItemUploadHandles.isNotEmpty) {
      await uploadPlan.createBundleHandlesFromDataItemHandles(
        fileDataItemUploadHandles: fileDataItemUploadHandles,
        folderDataItemUploadHandles: folderDataItemUploadHandles,
        turboService: turboService,
      );
    }
    return uploadPlan;
  }

  Future<void> createBundleHandlesFromDataItemHandles({
    Map<String, FileDataItemUploadHandle> fileDataItemUploadHandles = const {},
    Map<String, FolderDataItemUploadHandle> folderDataItemUploadHandles =
        const {},
    required TurboService turboService,
  }) async {
    // Set bundle size limit according the platform
    // This should be reviewed when we implement stream uploads
    useTurbo = await canWeUseTurbo(
      fileDataItemUploadHandles: fileDataItemUploadHandles,
      fileV2UploadHandles: fileV2UploadHandles,
      turboService: turboService,
    );
    const approximateMetadataSize = 200; //Usually less than 50 bytes
    final int maxBundleSize = useTurbo
        ? turboService.allowedDataItemSize + approximateMetadataSize
        : (kIsWeb ? bundleSizeLimit : mobileBundleSizeLimit);
    final int filesPerBundle = useTurbo ? 2 : maxFilesPerBundle;
    final bundleItems = await NextFitBundlePacker<UploadHandle>(
      maxBundleSize: maxBundleSize,
      maxDataItemCount: filesPerBundle,
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
        useTurbo: useTurbo,
      );
      bundleUploadHandles.add(bundleToUpload);
      uploadHandles.clear();
    }
    fileDataItemUploadHandles.clear();
  }
}

Future<bool> canWeUseTurbo({
  required Map<String, FileDataItemUploadHandle> fileDataItemUploadHandles,
  required Map<String, FileV2UploadHandle> fileV2UploadHandles,
  required TurboService turboService,
}) async {
  if (!turboService.useTurbo) return false;

  final allFileSizesAreWithinTurboThreshold =
      !fileDataItemUploadHandles.values.any((file) {
    return file.size > turboService.allowedDataItemSize;
  });

  return turboService.useTurbo &&
      fileV2UploadHandles.isEmpty &&
      allFileSizesAreWithinTurboThreshold;
}
