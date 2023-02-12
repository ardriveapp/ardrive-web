import 'package:ardrive/utils/streams.dart';
import 'package:flutter/foundation.dart';
import 'package:test/test.dart';

main() {
  group('trimData function', () {
    test('correct when at boundary', () {
      final data = [10, 10, 10, 10].map((n) => Uint8List(n));
      final input = Stream.fromIterable(data);
      final output = input.transform(trimData(30));
      expect(
        output,
        emitsInOrder([
          hasLength(10),
          hasLength(10),
          hasLength(10),
        ])
      );
    });

    test('trims data when not at boundary', () {
      final data = [9, 9, 9, 9].map((n) => Uint8List(n));
      final input = Stream.fromIterable(data);
      final output = input.transform(trimData(30));
      expect(
        output,
        emitsInOrder([
          hasLength(9),
          hasLength(9),
          hasLength(9),
          hasLength(3),
        ])
      );
    });
  });
}
