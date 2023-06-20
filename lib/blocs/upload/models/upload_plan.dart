import 'package:ardrive/blocs/upload/limits.dart';
import 'package:ardrive/blocs/upload/upload_handles/bundle_upload_handle.dart';
import 'package:ardrive/blocs/upload/upload_handles/folder_data_item_upload_handle.dart';
import 'package:ardrive/blocs/upload/upload_handles/upload_handle.dart';
import 'package:ardrive/services/turbo/upload_service.dart';
import 'package:ardrive/utils/bundles/next_fit_bundle_packer.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:flutter/foundation.dart';

import '../upload_handles/file_data_item_upload_handle.dart';
import '../upload_handles/file_v2_upload_handle.dart';

class UploadPlan {
  /// A map of [FileV2UploadHandle]s keyed by their respective file's id.
  late Map<String, FileV2UploadHandle> fileV2UploadHandles;

  final List<BundleUploadHandle> bundleUploadHandles = [];

  final int maxBundleSize;

  UploadPlan._create({
    required this.fileV2UploadHandles,
    required this.maxBundleSize,
  });

  static Future<UploadPlan> create({
    required Map<String, FileV2UploadHandle> fileV2UploadHandles,
    required Map<String, FileDataItemUploadHandle> fileDataItemUploadHandles,
    required Map<String, FolderDataItemUploadHandle>
        folderDataItemUploadHandles,
    required TurboUploadService turboUploadService,
    required int maxBundleSize,
  }) async {
    final uploadPlan = UploadPlan._create(
      fileV2UploadHandles: fileV2UploadHandles,
      maxBundleSize: maxBundleSize,
    );

    if (fileDataItemUploadHandles.isNotEmpty ||
        folderDataItemUploadHandles.isNotEmpty) {
      await uploadPlan.createBundleHandlesFromDataItemHandles(
        fileDataItemUploadHandles: fileDataItemUploadHandles,
        folderDataItemUploadHandles: folderDataItemUploadHandles,
        turboUploadService: turboUploadService,
        maxFilesPerBundle: maxBundleSize,
      );
    }
    return uploadPlan;
  }

  Future<void> createBundleHandlesFromDataItemHandles({
    Map<String, FileDataItemUploadHandle> fileDataItemUploadHandles = const {},
    Map<String, FolderDataItemUploadHandle> folderDataItemUploadHandles =
        const {},
    required TurboUploadService turboUploadService,
    required int maxFilesPerBundle,
  }) async {
    logger.i('Creating bundle handles from data item handles...');
    logger.i('max files per bundle: $maxFilesPerBundle');
    final int maxBundleSize =
        (kIsWeb ? bundleSizeLimit : mobileBundleSizeLimit);

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

// Future<bool> canWeUseTurbo({
//   required Map<String, FileDataItemUploadHandle> fileDataItemUploadHandles,
//   required Map<String, FileV2UploadHandle> fileV2UploadHandles,
//   required TurboUploadService turboUploadService,
// }) async {
//   if (!turboUploadService.useTurboUpload) return false;

//   final allFileSizesAreWithinTurboThreshold =
//       !fileDataItemUploadHandles.values.any((file) {
//     return file.size > turboUploadService.allowedDataItemSize;
//   });

//   return turboUploadService.useTurboUpload &&
//       fileV2UploadHandles.isEmpty &&
//       allFileSizesAreWithinTurboThreshold;
// }
