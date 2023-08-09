import 'package:ardrive/utils/truncate_string.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('truncatedString method', () {
    test('works fine with a healty input', () {
      const input = '1234567890';
      const output = '123...890';
      expect(truncateString(input, offsetStart: 3, offsetEnd: 3), output);
    });

    test(
      'throws when the sum of the offsets is bigger than the length of the text',
      () {
        const input = '1234567890';
        expect(
          () => truncateString(input, offsetStart: 6, offsetEnd: 6),
          throwsException,
        );
      },
    );
  });
}
