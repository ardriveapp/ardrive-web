import 'package:ardrive/utils/file_size_units.dart';
import 'package:ardrive_utils/ardrive_utils.dart';

class FileStorageEstimator {
  static double computeStorageEstimateForCredits({
    required BigInt credits,
    required FileSizeUnit outputDataUnit,
    required BigInt costOfOneGb,
  }) {
    final estimatedStorageInBytes =
        (credits.toDouble() * const GiB(1).size) / costOfOneGb.toDouble();

    switch (outputDataUnit) {
      case FileSizeUnit.bytes:
        return estimatedStorageInBytes;
      case FileSizeUnit.kilobytes:
        return estimatedStorageInBytes / const KiB(1).size;
      case FileSizeUnit.megabytes:
        return estimatedStorageInBytes / const MiB(1).size;
      case FileSizeUnit.gigabytes:
        return estimatedStorageInBytes / const GiB(1).size;
    }
  }
}
