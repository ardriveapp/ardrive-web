import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_crypto/ardrive_crypto.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:test/test.dart';

void main() {
  group('shouldLogErrorCallback Tests', () {
    test('should return false for ActionCanceledException', () {
      final error = ActionCanceledException();
      final result = shouldLogErrorCallback(error);
      expect(result, isFalse);
    });

    test(
        'should return false for buggy TransactionDecryptionException versions',
        () {
      const buggyVersions = [
        '2.30.0',
        '2.30.1',
        '2.30.2',
        '2.32.0',
        '2.36.0',
        '2.37.0',
        '2.37.1'
      ];
      for (var version in buggyVersions) {
        final error =
            TransactionDecryptionException(corruptedDataAppVersion: version);
        final result = shouldLogErrorCallback(error);
        expect(result, isFalse, reason: 'Failed for version $version');
      }
    });

    test(
        'should return true for non-buggy TransactionDecryptionException versions',
        () {
      const nonBuggyVersion = '2.31.0'; // Example of a non-buggy version
      final error = TransactionDecryptionException(
          corruptedDataAppVersion: nonBuggyVersion);
      final result = shouldLogErrorCallback(error);
      expect(result, isTrue);
    });

    test('should return true for other exceptions', () {
      final error = Exception('Some other exception');
      final result = shouldLogErrorCallback(error);
      expect(result, isTrue);
    });
  });
}
