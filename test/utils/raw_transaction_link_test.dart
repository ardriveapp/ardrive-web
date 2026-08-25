import 'package:ardrive/utils/raw_transaction_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const txId = 'nS7hxbLQmk3W1o9zX2cV4bN5mL6kJ7hG8fD9sA0qWeR';

  group('buildRawTransactionViewLocation', () {
    test('builds the bare route when there is nothing to hint', () {
      expect(
        buildRawTransactionViewLocation(txId: txId),
        '/view/$txId',
      );
    });

    test('carries the name and content type hints of §1.3', () {
      expect(
        buildRawTransactionViewLocation(
          txId: txId,
          name: 'talk.mp4',
          contentType: 'video/mp4',
        ),
        '/view/$txId?n=talk.mp4&ct=video%2Fmp4',
      );
    });

    test('percent-encodes a space as %20, not +', () {
      expect(
        buildRawTransactionViewLocation(txId: txId, name: 'Q3 Report.pdf'),
        '/view/$txId?n=Q3%20Report.pdf',
      );
    });

    test('never writes a hint the parser would drop', () {
      // One validator for both directions: a hint that would not survive the
      // trip is not worth the bytes.
      expect(
        buildRawTransactionViewLocation(
          txId: txId,
          name: 'a' * 200,
          contentType: 'not-a-mime-type',
        ),
        '/view/$txId',
      );
    });

    test('treats an empty hint as an absent one', () {
      expect(
        buildRawTransactionViewLocation(txId: txId, name: '', contentType: ''),
        '/view/$txId',
      );
    });
  });
}
