import 'package:ardrive/utils/truncate_string.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('truncatedString method', () {
    test('works fine with a healty input', () {
      const input = '1234567890';
      const output = '123...890';
      expect(truncateString(input, offsetStart: 3, offsetEnd: 3), output);
    });

    // Six and four everywhere: the profile button showed six and six and the
    // publish dialog six and four for the same address (issue #2370).
    test('shortenId keeps the first six characters and the last four', () {
      expect(shortenId('iKryOeAbCdEfGhIjKlMnOpQrStUvWxYz0123ncoRjA'),
          'iKryOe...oRjA');
      expect(shortenId('0x1234567890abcdef1234567890abcdef12345678'),
          '0x1234...5678');
    });

    test('shortenId leaves an ID no longer than its short form whole', () {
      expect(shortenId('abcdefghijklm'), 'abcdefghijklm');
      expect(shortenId('abc'), 'abc');
      expect(shortenId('abcdefghijklmn'), 'abcdef...klmn');
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
