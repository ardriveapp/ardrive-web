import 'package:flutter_test/flutter_test.dart';
import 'package:ardrive/utils/format_date.dart';

void main() {
  group('formatDate', () {
    test('formats date correctly', () {
      final testDate = DateTime(2023, 9, 25, 9, 47, 25);
      final formattedDate = formatDate(testDate);

      // The exact string will depend on the local time zone of the test environment
      // So we'll check for the parts we can be certain about
      expect(formattedDate, contains('Sep 25 2023 09:47:25 AM'));
      expect(formattedDate, contains('GMT'));
    });

    test('handles different time zones', () {
      final testDate = DateTime.utc(2023, 9, 25, 9, 47, 25);
      final formattedDate = formatDate(testDate);

      expect(formattedDate, contains('Sep 25 2023 09:47:25 AM'));
      expect(formattedDate, contains('GMT+0')); // UTC time should be GMT+0
    });

    test('handles different months', () {
      final testDate = DateTime(2023, 12, 31, 23, 59, 59);
      final formattedDate = formatDate(testDate);

      expect(formattedDate, contains('Dec 31 2023 11:59:59 PM'));
    });

    test('handles different years', () {
      final testDate = DateTime(2024, 1, 1, 0, 0, 0);
      final formattedDate = formatDate(testDate);

      expect(formattedDate, contains('Jan 1 2024 12:00:00 AM'));
    });
  });
}
