import 'package:ardrive/utils/snapshots/range.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Range class', () {
    test('throws if start is greater than end', () {
      expect(
        () => Range(start: 2, end: 1),
        throwsA(isA<BadRange>()),
      );
      expect(
        () => Range(start: -1, end: -2),
        throwsA(isA<BadRange>()),
      );
    });

    test('can be constructed with healthy inputs', () {
      Range range = Range(start: 0, end: 0);
      expect(range.start, 0);
      expect(range.end, 0);

      range = Range(start: 1, end: 2);
      expect(range.start, 1);
      expect(range.end, 2);

      range = Range(start: -2, end: -1);
      expect(range.start, -2);
      expect(range.end, -1);
    });

    test('equatability', () {
      Range rangeA = Range(start: 0, end: 0);
      Range rangeB = Range(start: 0, end: 0);
      expect(rangeA == rangeB, true);

      rangeA = Range(start: 50, end: 100);
      rangeB = Range(start: 50, end: 100);
      expect(rangeA == rangeB, true);
    });

    group('difference method', () {
      test('returns an empty array if B contains A', () {
        Range A = Range(start: 25, end: 50);
        Range B = Range(start: 0, end: 100);
        List<Range> diff = Range.difference(A, B);
        expect(diff, []);

        A = Range(start: 25, end: 50);
        B = Range(start: 25, end: 50);
        diff = Range.difference(A, B);
        expect(diff, []);
      });

      test('returns A if the ranges don\'t overlap', () {
        final Range A = Range(start: 0, end: 25);
        final Range B = Range(start: 50, end: 100);
        final diff = Range.difference(A, B);
        expect(diff.length, 1);
        expect(diff[0], A);
      });

      test('returns two ranges if B is included in A, but A is not in B', () {
        final A = Range(start: 0, end: 100);
        final B = Range(start: 25, end: 50);
        final diff = Range.difference(A, B);
        expect(diff.length, 2);
        final diff_1 = diff[0];
        final diff_2 = diff[1];
        expect(diff_1.start, 0);
        expect(diff_1.end, 24);
        expect(diff_2.start, 51);
        expect(diff_2.end, 100);
      });

      test('returns a single range if B intersects A', () {
        Range A = Range(start: 50, end: 100);
        Range B = Range(start: 75, end: 200);
        List<Range> diff = Range.difference(A, B);
        expect(diff.length, 1);
        expect(diff[0].start, 50);
        expect(diff[0].end, 74);

        A = Range(start: 50, end: 100);
        B = Range(start: 0, end: 50);
        diff = Range.difference(A, B);
        expect(diff.length, 1);
        expect(diff[0].start, 51);
        expect(diff[0].end, 100);
      });
    });

    group('intersection method', () {
      test('returns an empty array for ranges that don\'t overlap', () {
        final A = Range(start: 0, end: 50);
        final B = Range(start: 51, end: 100);
        final intersection = Range.intersection(A, B);
        expect(intersection, null);
      });

      test('returns a sub-range of the inputs partially intersect', () {
        Range A = Range(start: 0, end: 100);
        Range B = Range(start: 50, end: 100);
        Range intersection = Range.intersection(A, B)!;
        expect(intersection.start, B.start);
        expect(intersection.end, B.end);

        A = Range(start: 0, end: 100);
        B = Range(start: 0, end: 50);
        intersection = Range.intersection(A, B)!;
        expect(intersection.start, B.start);
        expect(intersection.end, B.end);

        A = Range(start: 0, end: 100);
        B = Range(start: 50, end: 150);
        intersection = Range.intersection(A, B)!;
        expect(intersection.start, 50);
        expect(intersection.end, 100);
      });

      test('returns A if B includes A', () {
        Range A = Range(start: 25, end: 50);
        Range B = Range(start: 0, end: 100);
        Range intersection = Range.intersection(A, B)!;
        expect(intersection.start, A.start);
        expect(intersection.end, A.end);

        A = Range(start: 0, end: 100);
        B = Range(start: 0, end: 100);
        intersection = Range.intersection(A, B)!;
        expect(intersection.start, A.start);
        expect(intersection.end, A.end);
      });
    });

    group('union method', () {
      test('returns two sub-ranges if the inputs don\'t intersect', () {
        final A = Range(start: 0, end: 24);
        final B = Range(start: 26, end: 100);
        final union = Range.union(A, B);
        expect(union.length, 2);
        expect(union[0].start, A.start);
        expect(union[0].end, A.end);
        expect(union[1].start, B.start);
        expect(union[1].end, B.end);
      });

      test('returns a single sub-range if the inputs does intersect', () {
        Range A = Range(start: 0, end: 50);
        Range B = Range(start: 25, end: 100);
        List<Range> union = Range.union(A, B);
        expect(union.length, 1);
        expect(union[0].start, 0);
        expect(union[0].end, 100);

        A = Range(start: 0, end: 50);
        B = Range(start: 51, end: 100);
        union = Range.union(A, B);
        expect(union.length, 1);
        expect(union[0].start, 0);
        expect(union[0].end, 100);
      });
    });
  });
}
