import 'package:ardrive/utils/snapshots/height_range.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HeightRange class', () {
    test('throws if fed with non-positive integers', () {});
    test('can be constructed with healthy inputs', () {});
    group('difference method', () {
      final List<DiffExpectation> expectations = [
        DiffExpectation(
            description:
                'returns two ranges if B is included in A, but A is not in B',
            input: DiffExpectationInput(
                A: HeightRange(rangeSegments: [Range(start: 0, end: 100)]),
                B: HeightRange(rangeSegments: [Range(start: 50, end: 50)])),
            result: HeightRange(rangeSegments: [
              Range(start: 0, end: 49),
              Range(start: 51, end: 100)
            ])),
        DiffExpectation(
            description: 'returns an empty array if B contains A',
            input: DiffExpectationInput(
                A: HeightRange(rangeSegments: [Range(start: 0, end: 100)]),
                B: HeightRange(rangeSegments: [
                  Range(start: 0, end: 50),
                  Range(start: 51, end: 100)
                ])),
            result: HeightRange(rangeSegments: [])),
        DiffExpectation(
            description: "returns A if the ranges don't overlap",
            input: DiffExpectationInput(
                A: HeightRange(rangeSegments: [Range(start: 0, end: 100)]),
                B: HeightRange(rangeSegments: [])),
            result: HeightRange(rangeSegments: [Range(start: 0, end: 100)])),
        DiffExpectation(
            description: 'returns a single range if B intersects A',
            input: DiffExpectationInput(
                A: HeightRange(rangeSegments: [Range(start: 0, end: 100)]),
                B: HeightRange(rangeSegments: [
                  Range(start: 0, end: 50),
                  Range(start: 99, end: 2000)
                ])),
            result: HeightRange(rangeSegments: [Range(start: 51, end: 98)])),
        DiffExpectation(
            description:
                'returns an empty range if all sub-ranges of B are shadowed by A',
            input: DiffExpectationInput(
                A: HeightRange(rangeSegments: [
                  Range(start: 0, end: 0),
                  Range(start: 100, end: 101)
                ]),
                B: HeightRange(rangeSegments: [
                  Range(start: 0, end: 50),
                  Range(start: 99, end: 2000)
                ])),
            result: HeightRange(rangeSegments: []))
      ];

      for (DiffExpectation expectation in expectations) {
        test(expectation.description, () {
          final A = expectation.input.A;
          final B = expectation.input.B;
          final diff = HeightRange.difference(A, B);
          for (int index = 0; index < diff.rangeSegments.length; index++) {
            final range = diff.rangeSegments[index];
            final expectedValue = expectation.result.rangeSegments[index];
            expect(range.start, expectedValue.start);
            expect(range.end, expectedValue.end);
          }
        });
      }
    });

    group('union method', () {
      test('preserves the amount of sub-ranges if thise don\'t intersect', () {
        final A = HeightRange(rangeSegments: [Range(start: 0, end: 25)]);
        final B = HeightRange(rangeSegments: [
          Range(start: 50, end: 100),
          Range(start: 150, end: 200)
        ]);
        final union = HeightRange.union(A, B);

        expect(union.rangeSegments.length, 3);
        expect(
            union.rangeSegments,
            containsAll([
              A.rangeSegments[0],
              B.rangeSegments[0],
              B.rangeSegments[1],
            ]));
      });

      test('returns a single sub-range if all of them intersect', () {
        final A = HeightRange(rangeSegments: [Range(start: 0, end: 200)]);
        final B = HeightRange(rangeSegments: [
          Range(start: 50, end: 100),
          Range(start: 150, end: 250)
        ]);
        final union = HeightRange.union(A, B);

        expect(union.rangeSegments.length, 1);
        expect(union.rangeSegments[0].start, 0);
        expect(union.rangeSegments[0].end, 250);
      });

      test(
          'returns more than 1 and less than the total if some of them intersect',
          () {
        final A = HeightRange(rangeSegments: [Range(start: 0, end: 25)]);
        final B = HeightRange(rangeSegments: [
          Range(start: 26, end: 100),
          Range(start: 150, end: 200)
        ]);
        final union = HeightRange.union(A, B);

        expect(union.rangeSegments.length, 2);
        expect(union.rangeSegments[0].start, 0);
        expect(union.rangeSegments[0].end, 100);
        expect(union.rangeSegments[1].start, 150);
        expect(union.rangeSegments[1].end, 200);
      });
    });
  });
}

class DiffExpectation {
  String description;
  DiffExpectationInput input;
  HeightRange result;

  DiffExpectation({
    required this.description,
    required this.input,
    required this.result,
  });
}

class DiffExpectationInput {
  HeightRange A;
  HeightRange B;

  DiffExpectationInput({
    required this.A,
    required this.B,
  });
}
