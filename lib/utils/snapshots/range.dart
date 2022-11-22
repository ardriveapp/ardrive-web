import 'dart:math';

import 'package:equatable/equatable.dart';

class Range {
  final int start;
  final int end;

  Range({required this.start, required this.end}) {
    if (start > end) {
      throw BadRange(start: start, end: end);
    }
  }

  bool isInRange(int value) {
    bool inRange = value >= start && value <= end;
    return inRange;
  }

  static final nullRange = Range(start: -1, end: -1);

  static List<Range> union(Range r_1, Range r_2) {
    final intersection = Range.intersection(r_1, r_2);
    final endOfR1TouchesStartOfR2 = r_1.end + 1 == r_2.start;
    final endOfR2TouchesStartOfR1 = r_2.end + 1 == r_1.start;
    final rangesAreContiguous =
        endOfR1TouchesStartOfR2 || endOfR2TouchesStartOfR1;
    if (intersection != null || rangesAreContiguous) {
      final unionStart = min(r_1.start, r_2.start);
      final unionEnd = max(r_1.end, r_2.end);
      final union = Range(start: unionStart, end: unionEnd);
      return [union];
    }
    return [r_1, r_2];
  }

  static List<Range> difference(Range r_1, Range r_2) {
    final intersection = Range.intersection(r_1, r_2);

    if (intersection != null) {
      final startsMatch = intersection.start == r_1.start;
      final endsMatch = intersection.end == r_1.end;
      if (startsMatch && endsMatch) {
        // r_1 is fully included in r_2, the diff is void
        return [];
      } else if (startsMatch) {
        // the intersection matches the start of r_1; the difference is at the end
        final diff = Range(start: intersection.end + 1, end: r_1.end);
        return [diff];
      } else if (endsMatch) {
        // the intersection matches the end of r_1; the difference is at the start
        final diff = Range(start: r_1.start, end: intersection.start - 1);
        return [diff];
      } else {
        // neither of the limits matches, r_2 is included in r_1; the difference is at the start and end
        final diffStart = Range(start: r_1.start, end: intersection.start - 1);
        final diffEnd = Range(start: intersection.end + 1, end: r_1.end);
        return [diffStart, diffEnd];
      }
    }

    // ranges don't intersect, the difference is the whole r_1
    return [r_1];
  }

  static Range? intersection(Range r_1, Range r_2) {
    final startOfR2FallsInR1 = r_2.start >= r_1.start && r_1.end >= r_2.start;

    final endOfR2FallsInR1 = r_2.end <= r_1.end && r_1.start <= r_2.end;
    final somePointOfR_2FallsInR_1 = startOfR2FallsInR1 || endOfR2FallsInR1;
    final r1IsFullyIncludedInR2 = r_1.start > r_2.start && r_1.end < r_2.end;

    if (somePointOfR_2FallsInR_1) {
      final intersectionStart = max(r_1.start, r_2.start);
      final intersectionEnd = min(r_1.end, r_2.end);
      return Range(start: intersectionStart, end: intersectionEnd);
    } else if (r1IsFullyIncludedInR2) {
      return r_1;
    }

    // the ranges don't intersect
    return null;
  }

  @override
  String toString() {
    return 'Range: ($start; $end)';
  }
}

class BadRange implements Exception, Equatable {
  final int start;
  final int end;
  BadRange({required this.start, required this.end});

  @override
  List<Object?> get props => [start, end];

  @override
  bool? get stringify => true;

  @override
  String toString() {
    return 'Bad range: ($start; $end)';
  }
}
