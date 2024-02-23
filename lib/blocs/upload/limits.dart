import 'package:ardrive_utils/ardrive_utils.dart';

final fileSizeLimit = const GiB(65).size;
final fileSizeWarning = const GiB(5).size;

const maxBundleDataItemCount = 500;
const maxFilesPerBundle = maxBundleDataItemCount ~/ 2;
const maxFilesSizePerBundleUsingTurbo = 1;

final d2nBundleSizeLimit = const GiB(65).size;
final turboBundleSizeLimit = const GiB(10).size;

int getBundleSizeLimit(bool isTurbo) =>
    isTurbo ? turboBundleSizeLimit : d2nBundleSizeLimit;
