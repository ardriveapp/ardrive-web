import 'package:ardrive/utils/snapshots/range.dart';
import 'package:equatable/equatable.dart';

class HeightRange {
  final List<Range> rangeSegments;

  HeightRange({required this.rangeSegments}) {
    for (Range range in rangeSegments) {
      if (range.start < 0 || range.end < 0) {
        throw BadHeightRange(start: range.start, end: range.end);
      }
    }
  }

  static HeightRange difference(HeightRange r_1, HeightRange r_2) {
    List<Range> prevDiff = r_1.rangeSegments;
    for (final range_2 in r_2.rangeSegments) {
      final List<Range> currDiff = [];
      for (final range_1 in prevDiff) {
        currDiff.addAll(Range.difference(range_1, range_2));
      }
      prevDiff = currDiff;
    }
    final diff = prevDiff;
    return HeightRange(rangeSegments: diff);
  }

  static HeightRange union(HeightRange r_1, HeightRange r_2) {
    final mixedRanges = [...r_1.rangeSegments, ...r_2.rangeSegments];
    final normalizedRanges = HeightRange._normalizeSegments(mixedRanges);
    final union = HeightRange(rangeSegments: normalizedRanges);
    return union;
  }

  static List<Range> _normalizeSegments(List<Range> rangeSegments) {
    final sortedSegments = List.castFrom<Range, Range>(rangeSegments)
      ..sort((a, b) => a.start - b.start);
    final List<Range> normalized = [];

    Range value = sortedSegments[0];
    for (var element in sortedSegments.skip(1)) {
      // Compute the union of both ranges
      final union = Range.union(value, element);
      if (union.length == 1) {
        // If they overlaps, then a single union range is returned
        // We are gonna keep making the union unil there are two elements
        value = union[0];
      } else {
        // Here there are two elements in the union: there's no overlap
        // There's a space in between the two values, and as they are sorted
        // then union[0] wont overlap with any other range segment.
        normalized.add(union[0]);

        // We have to keep looping with the rest of elements in order to check
        // if union[1] overlaps with another range segment.
        value = union[1];
      }
    }
    normalized.add(value);
    return normalized;
  }
}

class BadHeightRange implements Exception, Equatable {
  final int start;
  final int end;
  BadHeightRange({required this.start, required this.end});

  @override
  List<Object?> get props => [start, end];

  @override
  bool? get stringify => true;

  @override
  String toString() {
    return 'Bad height range: ($start; $end)';
  }
}
