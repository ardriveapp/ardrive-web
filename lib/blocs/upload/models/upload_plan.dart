import 'package:ardrive/blocs/upload/limits.dart';
import 'package:ardrive/blocs/upload/upload_handles/bundle_upload_handle.dart';
import 'package:ardrive/blocs/upload/upload_handles/folder_data_item_upload_handle.dart';
import 'package:ardrive/blocs/upload/upload_handles/upload_handle.dart';
import 'package:ardrive/services/turbo/upload_service.dart';
import 'package:ardrive/utils/bundles/next_fit_bundle_packer.dart';
import 'package:flutter/foundation.dart';

import '../upload_handles/file_data_item_upload_handle.dart';
import '../upload_handles/file_v2_upload_handle.dart';

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
    required UploadService turboUploadService,
  }) async {
    final uploadPlan = UploadPlan._create(
      fileV2UploadHandles: fileV2UploadHandles,
    );
    if (fileDataItemUploadHandles.isNotEmpty ||
        folderDataItemUploadHandles.isNotEmpty) {
      await uploadPlan.createBundleHandlesFromDataItemHandles(
        fileDataItemUploadHandles: fileDataItemUploadHandles,
        folderDataItemUploadHandles: folderDataItemUploadHandles,
        turboUploadService: turboUploadService,
      );
    }
    return uploadPlan;
  }

  Future<void> createBundleHandlesFromDataItemHandles({
    Map<String, FileDataItemUploadHandle> fileDataItemUploadHandles = const {},
    Map<String, FolderDataItemUploadHandle> folderDataItemUploadHandles =
        const {},
    required UploadService turboUploadService,
  }) async {
    // Set bundle size limit according the platform
    // This should be reviewed when we implement stream uploads
    useTurbo = await canWeUseTurbo(
      fileDataItemUploadHandles: fileDataItemUploadHandles,
      fileV2UploadHandles: fileV2UploadHandles,
      turboUploadService: turboUploadService,
    );
    const approximateMetadataSize = 200; //Usually less than 50 bytes
    final int maxBundleSize = useTurbo
        ? turboUploadService.allowedDataItemSize + approximateMetadataSize
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
  required UploadService turboUploadService,
}) async {
  if (!turboUploadService.useTurboUpload) return false;

  final allFileSizesAreWithinTurboThreshold =
      !fileDataItemUploadHandles.values.any((file) {
    return file.size > turboUploadService.allowedDataItemSize;
  });

  return turboUploadService.useTurboUpload &&
      fileV2UploadHandles.isEmpty &&
      allFileSizesAreWithinTurboThreshold;
}
