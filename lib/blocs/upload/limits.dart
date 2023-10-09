import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/foundation.dart';

final privateFileSizeLimit = const MiB(100000).size;

final mobilePrivateFileSizeLimit = const GiB(10).size;

final publicFileSafeSizeLimit = const GiB(5).size;

final bundleSizeLimit = kIsWeb ? webBundleSizeLimit : mobileBundleSizeLimit;

final webBundleSizeLimit = const MiB(65000).size;
final mobileBundleSizeLimit = const MiB(65000).size;
const maxBundleDataItemCount = 500;
const maxFilesPerBundle = maxBundleDataItemCount ~/ 2;
const maxFilesSizePerBundleUsingTurbo = 1;
