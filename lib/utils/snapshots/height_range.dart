import 'package:ardrive/utils/snapshots/range.dart';

class HeightRange {
  final List<Range> rangeSegments;

  HeightRange({required this.rangeSegments});

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
