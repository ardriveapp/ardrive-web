import 'package:ardrive/utils/usd_upload_cost_to_string.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('usdUploadCostToString method', () {
    test('returns the formatted value with two digits of precision', () {
      const usdUploadCost = 0.01;
      final result = usdUploadCostToString(usdUploadCost);

      expect(result, ' (~0.01 USD)');
    });

    test('returns the formatted value with as "less than"', () {
      const usdUploadCost = 0.009;
      final result = usdUploadCostToString(usdUploadCost);

      expect(result, ' (< 0.01 USD)');
    });
  });
}
