import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

// Every date the app shows goes through these two, in the reader's own time
// zone. With some views in local time and others in UTC, one item read as two
// different days near midnight.

/// A day, such as "Oct 12, 2026".
String formatDate(DateTime date) => DateFormat.yMMMd().format(date.toLocal());

/// A day and a time with its zone, such as "Oct 12, 2026 12:01:01 AM GMT-4".
///
/// The time and its zone are joined by non-breaking spaces, so a narrow
/// column wraps after the day instead of leaving the zone on a line of its
/// own.
String formatDateTime(DateTime date) {
  final local = date.toLocal();
  final time = '${DateFormat.jms().format(local)} '
      '${formatUtcOffset(local.timeZoneOffset)}';

  // intl already puts a narrow no-break space (U+202F) before AM and PM.
  return '${formatDate(local)} '
      '${time.replaceAll(RegExp('[ \u202F]'), '\u00A0')}';
}

/// The zone as its offset from UTC, such as "GMT-4" or "GMT+5:30".
///
/// Zone names from the browser vary by platform and are often long, such as
/// "Eastern Daylight Time", so the offset is shown instead.
@visibleForTesting
String formatUtcOffset(Duration offset) {
  final sign = offset.isNegative ? '-' : '+';
  final minutes = offset.inMinutes.abs();
  final hours = minutes ~/ 60;
  final rest = minutes % 60;

  return rest == 0
      ? 'GMT$sign$hours'
      : 'GMT$sign$hours:${rest.toString().padLeft(2, '0')}';
}
