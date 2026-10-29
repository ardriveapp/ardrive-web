import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _fontAsset = 'packages/ardrive_ui/assets/fonts/ArDriveIcons.ttf';

/// A table of the font, by its four-letter tag.
ByteData _table(ByteData font, String tag) {
  final count = font.getUint16(4);
  for (var i = 0; i < count; i++) {
    final record = 12 + i * 16;
    final name = String.fromCharCodes(
      font.buffer.asUint8List(font.offsetInBytes + record, 4),
    );
    if (name == tag) {
      return ByteData.sublistView(
        font,
        font.getUint32(record + 8),
        font.getUint32(record + 8) + font.getUint32(record + 12),
      );
    }
  }
  throw StateError('no $tag table');
}

/// Each drawn glyph's left side bearing in `hmtx` and the left edge of its
/// outline in `glyf`, in font units.
List<({int glyph, int lsb, int xMin})> _sideBearings(ByteData font) {
  final head = _table(font, 'head');
  final maxp = _table(font, 'maxp');
  final hhea = _table(font, 'hhea');
  final hmtx = _table(font, 'hmtx');
  final loca = _table(font, 'loca');
  final glyf = _table(font, 'glyf');

  final longOffsets = head.getInt16(50) == 1;
  final glyphs = maxp.getUint16(4);
  final hMetrics = hhea.getUint16(34);

  int offset(int glyph) =>
      longOffsets ? loca.getUint32(glyph * 4) : loca.getUint16(glyph * 2) * 2;

  int lsb(int glyph) => glyph < hMetrics
      ? hmtx.getInt16(glyph * 4 + 2)
      : hmtx.getInt16(hMetrics * 4 + (glyph - hMetrics) * 2);

  return [
    for (var glyph = 0; glyph < glyphs; glyph++)
      // An empty glyph has no outline, so nothing to place.
      if (offset(glyph + 1) > offset(glyph))
        (
          glyph: glyph,
          lsb: lsb(glyph),
          xMin: glyf.getInt16(offset(glyph) + 2),
        ),
  ];
}

/// The columns [image] has ink in, as a fraction-free range.
({int left, int right}) _inkColumns(ByteData rgba, int width, int height) {
  var left = width;
  var right = -1;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (rgba.getUint8((y * width + x) * 4 + 3) > 0) {
        if (x < left) left = x;
        if (x > right) right = x;
      }
    }
  }
  return (left: left, right: right);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A TrueType renderer that honours `hmtx` (FreeType: CanvasKit on the
  /// web, Android, Linux) places the outline so its left edge lands on the
  /// side bearing. One that ignores it (Core Text) draws the outline where
  /// it is. When the two disagree the glyph moves by the difference, and an
  /// X with lsb 0 and xMin 249 drew 6 px left of centre on the web only.
  ///
  /// Re-exporting the font from a tool that recalculates the outline bounds
  /// and not the metrics is what does it. To put it right:
  ///
  ///     from fontTools.ttLib import TTFont
  ///     f = TTFont('ArDriveIcons.ttf')
  ///     for n in f.getGlyphOrder():
  ///         g = f['glyf'][n]
  ///         if g.numberOfContours:
  ///             f['hmtx'][n] = (f['hmtx'][n][0], g.xMin)
  ///     f['head'].flags |= 2
  ///     f.save('ArDriveIcons.ttf')
  test('every icon glyph sits where its side bearing says', () async {
    final font = await rootBundle.load(_fontAsset);
    final glyphs = _sideBearings(font);

    expect(glyphs, isNotEmpty);
    for (final g in glyphs) {
      expect(
        g.lsb,
        g.xMin,
        reason: 'glyph ${g.glyph}: hmtx says its left edge is at ${g.lsb}, '
            'its outline starts at ${g.xMin}',
      );
    }
  });

  group('drawn with the real font', () {
    setUpAll(() async {
      final loader = FontLoader('packages/ardrive_ui/ArDriveIcons')
        ..addFont(rootBundle.load(_fontAsset));
      await loader.load();
    });

    /// Each of these is centred in the font's own em square, so drawn in a
    /// square box its ink is centred in the box.
    for (final (name, icon) in [
      ('x', ArDriveIconsData.x),
      ('arrow right', ArDriveIconsData.arrow_right_outline),
      ('menu', ArDriveIconsData.menu),
      ('sun', ArDriveIconsData.sun),
    ]) {
      testWidgets('the $name icon is centred in its box', (tester) async {
        const size = 48.0;
        final key = GlobalKey();

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: RepaintBoundary(
                key: key,
                child: Icon(icon, size: size, color: const Color(0xFF000000)),
              ),
            ),
          ),
        );

        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final ink = await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes =
              (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
          final columns = _inkColumns(bytes, image.width, image.height);
          image.dispose();
          return columns;
        });

        expect(ink!.right, greaterThan(ink.left), reason: 'nothing was drawn');
        final inkCentre = (ink.left + ink.right + 1) / 2;
        expect(
          inkCentre,
          moreOrLessEquals(size / 2, epsilon: 1.5),
          reason: 'ink spans columns ${ink.left}-${ink.right} of $size',
        );
      });
    }
  });
}
