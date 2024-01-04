import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('streamToUint8List', () {
    test('should return empty Uint8List for empty stream', () async {
      expect(await concatenateUint8ListStream(const Stream.empty()),
          equals(Uint8List(0)));
    });

    test('should handle single element stream', () async {
      Stream<Uint8List> stream = Stream.value(Uint8List.fromList([1, 2, 3]));
      expect(await concatenateUint8ListStream(stream),
          equals(Uint8List.fromList([1, 2, 3])));
    });

    test('should concatenate multiple elements in stream', () async {
      Stream<Uint8List> stream = Stream.fromIterable([
        Uint8List.fromList([1, 2]),
        Uint8List.fromList([3, 4]),
      ]);
      expect(await concatenateUint8ListStream(stream),
          equals(Uint8List.fromList([1, 2, 3, 4])));
    });

    test('should handle error in stream', () async {
      Stream<Uint8List> stream = Stream.fromFuture(Future.error('Error'));
      expect(concatenateUint8ListStream(stream), throwsA(isA<String>()));
    });
  });

  group('listIntToUint8ListTransformer', () {
    test('should transform empty list to empty Uint8List', () async {
      final Stream<Uint8List> stream =
          Stream.value(<int>[]).transform(listIntToUint8ListTransformer);
      expect(await stream.first, equals(Uint8List(0)));
    });

    test('should transform non-empty list to Uint8List', () async {
      final Stream<Uint8List> stream =
          Stream.value([1, 2, 3]).transform(listIntToUint8ListTransformer);
      expect(await stream.first, equals(Uint8List.fromList([1, 2, 3])));
    });
  });
}
