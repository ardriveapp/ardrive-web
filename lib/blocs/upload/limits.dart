import 'package:ardrive/utils/data_size.dart';
import 'package:flutter/foundation.dart';

final privateFileSizeLimit = const MiB(100).size;

final mobilePrivateFileSizeLimit = const GiB(1).size;

final publicFileSafeSizeLimit = const GiB(5).size;

final bundleSizeLimit = kIsWeb ? webBundleSizeLimit : mobileBundleSizeLimit;

final webBundleSizeLimit = const MiB(480).size;
final mobileBundleSizeLimit = const MiB(200).size;
const maxBundleDataItemCount = 500;
const maxFilesPerBundle = maxBundleDataItemCount ~/ 2;
