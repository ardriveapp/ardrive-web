import 'package:ardrive/utils/format_date.dart';
import 'package:test/test.dart';

// These hold in whatever time zone the tests run in.
void main() {
  // 03:57 UTC on Oct 12 is still Oct 11 in the Americas.
  final instant = DateTime.utc(2026, 10, 12, 3, 57, 35);

  group('formatDate', () {
    test('gives the day in the local time zone', () {
      expect(formatDate(DateTime(2026, 10, 11, 23, 30)), 'Oct 11, 2026');
    });

    test('gives the same day for an instant held in UTC or in local time', () {
      // A UTC value used to be formatted as its UTC day, so the same item
      // showed one day in a table and another in the details panel.
      expect(formatDate(instant), formatDate(instant.toLocal()));
    });
  });

  group('formatDateTime', () {
    test('gives the day, the time to the second and the zone', () {
      final local = DateTime(2026, 10, 12, 0, 1, 1);
      final text = formatDateTime(local);

      // The time and zone are held together with non-breaking spaces, so a
      // narrow column wraps after the day.
      expect(
        text,
        'Oct 12, 2026 12:01:01\u00A0AM\u00A0'
        '${formatUtcOffset(local.timeZoneOffset)}',
      );
    });

    test('gives the same text for an instant held in UTC or in local time', () {
      expect(formatDateTime(instant), formatDateTime(instant.toLocal()));
    });

    test('agrees with formatDate on the day', () {
      expect(formatDateTime(instant), startsWith(formatDate(instant)));
    });
  });

  group('formatUtcOffset', () {
    test('UTC', () {
      expect(formatUtcOffset(Duration.zero), 'GMT+0');
    });

    test('whole hours', () {
      expect(formatUtcOffset(const Duration(hours: -4)), 'GMT-4');
      expect(formatUtcOffset(const Duration(hours: 9)), 'GMT+9');
    });

    test('part hours', () {
      expect(
          formatUtcOffset(const Duration(hours: 5, minutes: 30)), 'GMT+5:30');
      expect(
          formatUtcOffset(const Duration(hours: -3, minutes: -30)), 'GMT-3:30');
      expect(
          formatUtcOffset(const Duration(hours: 12, minutes: 45)), 'GMT+12:45');
    });
  });
}
