import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('largeThumbnailSizeFor', () {
    test('a landscape image is 512 wide, in its proportions', () {
      expect(largeThumbnailSizeFor(width: 100, height: 66),
          (width: 512, height: 338));
    });

    test('a portrait image is 512 tall, not 512 wide', () {
      expect(largeThumbnailSizeFor(width: 100, height: 400),
          (width: 128, height: 512));
    });

    test('a square is 512 each way', () {
      expect(largeThumbnailSizeFor(width: 100, height: 100),
          (width: 512, height: 512));
    });

    test('a very thin image keeps at least a pixel', () {
      expect(largeThumbnailSizeFor(width: 1, height: 100000).width, 1);
    });

    test('an unknown size falls back to a square', () {
      expect(largeThumbnailSizeFor(width: 0, height: 0),
          (width: 512, height: 512));
    });
  });

  group('isWorthALargeThumbnail', () {
    test('yes when it is at least twice the small one', () {
      expect(
          isWorthALargeThumbnail(
              largeWidth: 512,
              largeHeight: 338,
              smallWidth: 100,
              smallHeight: 66),
          isTrue);
    });

    test('yes for a tall image, whose small one is already tall', () {
      // Web: a 1500 x 4000 photo's small thumbnail is 100 x 266.
      expect(
          isWorthALargeThumbnail(
              largeWidth: 192,
              largeHeight: 512,
              smallWidth: 100,
              smallHeight: 266),
          isTrue);
    });

    test('no when the image was too small to grow much', () {
      // A 150 px source: the small thumbnail is 100, the large one 150.
      expect(
          isWorthALargeThumbnail(
              largeWidth: 150,
              largeHeight: 150,
              smallWidth: 100,
              smallHeight: 100),
          isFalse);
    });
  });
}
