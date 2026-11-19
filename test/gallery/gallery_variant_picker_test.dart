import 'package:ardrive/gallery/image_loader/gallery_variant_picker.dart';
import 'package:flutter_test/flutter_test.dart';

GalleryVariant v(String id, int w, int h, [int size = 5000]) =>
    GalleryVariant(txId: id, size: size, width: w, height: h);

void main() {
  final small = v('small', 160, 120);
  final mid = v('mid', 512, 384);
  final original = v('orig', 4000, 3000, 1500000);

  String? pick({
    List<GalleryVariant> variants = const [],
    GalleryVariant? orig,
    double w = 200,
    double h = 150,
    bool isPrivate = false,
    bool onScreen = true,
    bool idle = true,
  }) =>
      chooseGalleryVariant(
        variants: variants,
        original: orig,
        tileWidthPx: w,
        tileHeightPx: h,
        isPrivate: isPrivate,
        onScreen: onScreen,
        idle: idle,
      )?.variant.txId;

  group('chooseGalleryVariant', () {
    test('smallest variant that covers the tile', () {
      expect(pick(variants: [mid, small], w: 150, h: 100), 'small');
      expect(pick(variants: [small, mid], w: 300, h: 200), 'mid');
    });

    test('devicePixelRatio is applied by the caller via pixel size', () {
      // 100x75 logical at 2x = 200x150 device px: small (160) is too small.
      expect(pick(variants: [small, mid], w: 200, h: 150), 'mid');
    });

    test('falls back to the largest variant when none covers', () {
      expect(pick(variants: [small, mid], w: 900, h: 700), 'mid');
    });

    test('original for a public image when no variant covers', () {
      expect(pick(variants: [small], orig: original), 'orig');
      expect(pick(variants: [], orig: original), 'orig');
    });

    test('a covering variant beats the original', () {
      expect(pick(variants: [small, mid], orig: original), 'mid');
    });

    test('original over 2 MB is not used', () {
      final big = v('big', 4000, 3000, 2 * 1024 * 1024 + 1);
      expect(pick(variants: [small], orig: big), 'small');
      expect(pick(variants: [], orig: big), isNull);
    });

    test('original at exactly 2 MB is used', () {
      final edge = v('edge', 4000, 3000, 2 * 1024 * 1024);
      expect(pick(variants: [], orig: edge), 'edge');
    });

    test('original only when idle and on screen', () {
      expect(pick(variants: [small], orig: original, idle: false), 'small');
      expect(pick(variants: [small], orig: original, onScreen: false), 'small');
    });

    test('private drives never use the original', () {
      expect(pick(variants: [small], orig: original, isPrivate: true), 'small');
      expect(pick(variants: [], orig: original, isPrivate: true), isNull);
    });

    test('an original of unknown (0) size is never eligible', () {
      expect(pick(variants: [small], orig: v('o', 4000, 3000, 0)), 'small');
      expect(pick(variants: [], orig: v('o', 4000, 3000, 0)), isNull);
    });

    test('variants with unknown dimensions rank last', () {
      final unknown = v('unk', 0, 0, 90000);
      expect(pick(variants: [unknown, small], w: 900, h: 700), 'small');
      expect(pick(variants: [unknown, small]), 'small');
      expect(pick(variants: [unknown, v('u2', 0, 0, 100)]), 'unk');
    });

    test('nothing eligible gives null', () {
      expect(pick(), isNull);
    });
  });
}
