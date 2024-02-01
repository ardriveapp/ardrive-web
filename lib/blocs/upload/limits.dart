import 'package:ardrive_utils/ardrive_utils.dart';

final privateFileSizeLimit = const GiB(65).size;

final largeFileUploadSizeThreshold = const MiB(500).size;

final mobilePrivateFileSizeLimit = const GiB(10).size;

final publicFileSafeSizeLimit = const GiB(5).size;
final nonChromeBrowserUploadSafeLimitUsingTurbo = const MiB(500).size;

int getBundleSizeLimit(bool isTurbo) =>
    isTurbo ? turboBundleSizeLimit : d2nBundleSizeLimit;

final d2nBundleSizeLimit = const GiB(65).size;
final turboBundleSizeLimit = const GiB(10).size;
final mobileBundleSizeLimit = const GiB(65).size;
const maxBundleDataItemCount = 500;
const maxFilesPerBundle = maxBundleDataItemCount ~/ 2;
const maxFilesSizePerBundleUsingTurbo = 1;
