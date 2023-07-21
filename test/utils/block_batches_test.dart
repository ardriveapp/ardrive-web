import 'package:ardrive/utils/block_batches.dart';
import 'package:test/test.dart';

void main() {
  group('Test blockBatches function', () {
    // Happy path test case
    test('Happy path', () {
      expect(
          blockBatches(1, 10, 2),
          equals([
            [1, 2],
            [3, 4],
            [5, 6],
            [7, 8],
            [9, 10]
          ]));
    });

    // Unhappy path test case
    test('Unhappy path', () {
      expect(
          blockBatches(1, 10, 3),
          equals([
            [1, 3],
            [4, 6],
            [7, 9],
            [10, 10]
          ]));
    });
  });
}
