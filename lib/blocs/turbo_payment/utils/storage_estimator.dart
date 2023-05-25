// enum for the units of the file size
// ignore: constant_identifier_names

import '../file_size_units.dart';

class FileStorageEstimator {
  static const double oneKilobyteInBytes = 1024;
  static const double oneMegabyteInBytes = oneKilobyteInBytes * 1024;
  static const double oneGigabyteInBytes = oneMegabyteInBytes * 1024;
  static const double oneTerabyteInBytes = oneGigabyteInBytes * 1024;

  static double computeStorageEstimateForCredits({
    required BigInt credits,
    required FileSizeUnit outputDataUnit,
    required BigInt costOfOneGb,
  }) {
    final estimatedStorageInBytes =
        (credits.toDouble() * oneGigabyteInBytes) / costOfOneGb.toDouble();

    switch (outputDataUnit) {
      case FileSizeUnit.bytes:
        return estimatedStorageInBytes;
      case FileSizeUnit.kilobytes:
        return estimatedStorageInBytes / oneKilobyteInBytes;
      case FileSizeUnit.megabytes:
        return estimatedStorageInBytes / oneMegabyteInBytes;
      case FileSizeUnit.gigabytes:
        return estimatedStorageInBytes / oneGigabyteInBytes;
      default:
        throw ArgumentError('Invalid outputDataUnit.');
    }
  }
}
