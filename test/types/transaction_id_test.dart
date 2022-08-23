import 'package:ardrive/types/transaction_id.dart';
import 'package:test/test.dart';

void main() {
  group('TransactionID type', () {
    const validTxId = '0000000000000000000000000000000000000000000';
    const anotherValidTxId = '1111111111111111111111111111111111111111111';
    const invalidTxId = 'an invalid TX ID value';

    test('accepts a valid TX ID', () {
      final txId = TransactionID(validTxId);
      expect(txId.toString(), validTxId);
    });

    test('throws if an invalid address is passed', () {
      expect(
        () => TransactionID(invalidTxId),
        throwsA(const TypeMatcher<InvalidTransactionId>()),
      );
    });

    test('equality', () {
      expect(TransactionID(validTxId) == TransactionID(validTxId), true);
      expect(
        TransactionID(validTxId) == TransactionID(anotherValidTxId),
        false,
      );
    });
  });
}
