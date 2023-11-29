import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/foundation.dart';

final privateFileSizeLimit = const GiB(65).size;

final largeFileUploadSizeThreshold = const MiB(500).size;

final mobilePrivateFileSizeLimit = const GiB(10).size;

final publicFileSafeSizeLimit = const GiB(5).size;
final nonChromeBrowserUploadSafeLimitUsingTurbo = const MiB(500).size;

int getBundleUploadSizeLimit(bool isTurbo, {bool? mockKIsWeb}) {
  // Use mockKIsWeb if it's provided, otherwise use the actual kIsWeb
  bool isWeb = mockKIsWeb ?? kIsWeb;

  if (isTurbo) {
    if (isWeb) {
      return turboWebPlatformsBundleSizeLimit;
    }
    return turboBundleSizeLimit;
  }

  return d2nBundleSizeLimit;
}

final d2nBundleSizeLimit = const GiB(65).size;
final turboWebPlatformsBundleSizeLimit = const MiB(500).size;
final turboBundleSizeLimit = const GiB(2).size;
final mobileBundleSizeLimit = const GiB(65).size;
const maxBundleDataItemCount = 500;
const maxFilesPerBundle = maxBundleDataItemCount ~/ 2;
const maxFilesSizePerBundleUsingTurbo = 1;
