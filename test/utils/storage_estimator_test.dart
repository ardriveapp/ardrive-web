import 'package:ardrive/utils/file_size_units.dart';
import 'package:ardrive/turbo/utils/storage_estimator.dart';
import 'package:test/test.dart';

void main() {
  group('FileStorageEstimator', () {
    test('Storage estimate in Gigabytes', () {
      final credits = BigInt.from(5000);
      final costOfOneGb = BigInt.from(50);
      final result = FileStorageEstimator.computeStorageEstimateForCredits(
        credits: credits,
        outputDataUnit: FileSizeUnit.gigabytes,
        costOfOneGb: costOfOneGb,
      );
      expect(result, 100); // (5000 credits / 50 credits/GB = 100 GB)
    });

    test('Storage estimate in Megabytes', () {
      final credits = BigInt.from(5000);
      final costOfOneGb = BigInt.from(50);
      final result = FileStorageEstimator.computeStorageEstimateForCredits(
        credits: credits,
        outputDataUnit: FileSizeUnit.megabytes,
        costOfOneGb: costOfOneGb,
      );
      expect(
        result,
        102400,
      ); // (5000 credits / 50 credits/GB = 100 GB = 102400 MB)
    });

    test('Converting down to a fraction', () {
      final credits = BigInt.from(25);
      final costOfOneGb = BigInt.from(50);
      final result = FileStorageEstimator.computeStorageEstimateForCredits(
        credits: credits,
        outputDataUnit: FileSizeUnit.gigabytes,
        costOfOneGb: costOfOneGb,
      );
      expect(
        result,
        0.5,
      );
    });
  });
}
