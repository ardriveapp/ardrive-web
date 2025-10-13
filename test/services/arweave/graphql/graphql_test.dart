import 'package:ardrive/services/arweave/graphql/graphql.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:test/test.dart';

void main() {
  group('TransactionMixinExtensions', () {
    group('getCommitTime', () {
      test('parses Unix-Time in seconds for ArFS != 0.10', () {
        // Unix timestamp for 2024-01-01 00:00:00 UTC
        const timestamp = 1704067200;
        final transaction = _MockTransaction(
          arfsVersion: '0.15',
          unixTime: timestamp.toString(),
        );

        final result = transaction.getCommitTime();

        expect(
          result,
          equals(DateTime.fromMillisecondsSinceEpoch(timestamp * 1000)),
        );
      });

      test('parses Unix-Time in milliseconds for ArFS 0.10', () {
        // Unix timestamp in milliseconds for 2024-01-01 00:00:00 UTC
        const timestampMs = 1704067200000;
        final transaction = _MockTransaction(
          arfsVersion: '0.10',
          unixTime: timestampMs.toString(),
        );

        final result = transaction.getCommitTime();

        expect(
          result,
          equals(DateTime.fromMillisecondsSinceEpoch(timestampMs)),
        );
      });

      test('detects and handles buggy millisecond timestamps for ArFS != 0.10',
          () {
        // Buggy case: Unix-Time was written as milliseconds instead of seconds
        // Unix timestamp in milliseconds for 2024-01-01 00:00:00 UTC
        const timestampMs = 1704067200000;
        final transaction = _MockTransaction(
          arfsVersion: '0.15',
          unixTime: timestampMs.toString(),
        );

        final result = transaction.getCommitTime();

        // Should detect it's already in milliseconds and not multiply by 1000
        expect(
          result,
          equals(DateTime.fromMillisecondsSinceEpoch(timestampMs)),
        );
      });

      test('correctly handles normal seconds timestamp (not too large)', () {
        // Normal timestamp in seconds for 2024-01-01 00:00:00 UTC
        const timestamp = 1704067200;
        final transaction = _MockTransaction(
          arfsVersion: '0.15',
          unixTime: timestamp.toString(),
        );

        final result = transaction.getCommitTime();

        // Should multiply by 1000 since it's in seconds
        expect(
          result,
          equals(DateTime.fromMillisecondsSinceEpoch(timestamp * 1000)),
        );
      });

      test('threshold detection works correctly', () {
        // Test value just below threshold (should be treated as seconds)
        const justBelowThreshold = 9999999999; // ~Nov 2286 in seconds
        final transaction1 = _MockTransaction(
          arfsVersion: '0.15',
          unixTime: justBelowThreshold.toString(),
        );

        final result1 = transaction1.getCommitTime();
        expect(
          result1,
          equals(
              DateTime.fromMillisecondsSinceEpoch(justBelowThreshold * 1000)),
        );

        // Test value just above threshold (should be treated as milliseconds)
        const justAboveThreshold = 10000000001; // Already in milliseconds
        final transaction2 = _MockTransaction(
          arfsVersion: '0.15',
          unixTime: justAboveThreshold.toString(),
        );

        final result2 = transaction2.getCommitTime();
        expect(
          result2,
          equals(DateTime.fromMillisecondsSinceEpoch(justAboveThreshold)),
        );
      });

      test('handles realistic current timestamps correctly', () {
        // Current timestamp in seconds (2024)
        const currentTimestamp = 1728777600;
        final transaction = _MockTransaction(
          arfsVersion: '0.15',
          unixTime: currentTimestamp.toString(),
        );

        final result = transaction.getCommitTime();

        // Just verify it's in the correct year range
        expect(result.year, equals(2024));
        expect(result.millisecondsSinceEpoch, equals(currentTimestamp * 1000));
      });
    });
  });
}

class _MockTransaction implements TransactionCommonMixin {
  final String arfsVersion;
  final String unixTime;

  _MockTransaction({
    required this.arfsVersion,
    required this.unixTime,
  });

  @override
  List<TransactionCommonMixin$Tag> get tags => [
        _MockTag(name: EntityTag.arFs, value: arfsVersion),
        _MockTag(name: EntityTag.unixTime, value: unixTime),
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockTag implements TransactionCommonMixin$Tag {
  @override
  final String name;

  @override
  final String value;

  _MockTag({required this.name, required this.value});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
