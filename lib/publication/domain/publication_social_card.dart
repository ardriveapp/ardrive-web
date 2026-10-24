import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ardrive/publication/domain/publication_images.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/rendering.dart' show CustomPainter;

/// The social card a page gets when its owner picks none (docs/
/// PUBLICATIONS.md, "The generated social card"): drawn here, at publish,
/// from what the owner typed and picked, and uploaded like any other image.
///
/// The same painter draws the dialog's preview, scaled, so what the owner
/// sees is what a link preview shows.
class PublicationSocialCard {
  const PublicationSocialCard({
    required this.title,
    required this.description,
    required this.fileCount,
    this.cover,
    this.icon,
    this.iconTint,
    required this.mark,
  });

  final String title;
  final String description;

  /// "N files", already worded.
  final String fileCount;
  final ui.Image? cover;
  final ui.Image? icon;

  /// The background's colour without a cover: [averageColor] of the icon.
  final Color? iconTint;

  /// ArDrive's mark, drawn small in a corner.
  final ui.Image mark;

  static const width = 1200.0;
  static const height = 630.0;

  /// The card as the page's `social.jpg`.
  Future<Uint8List> render() async {
    final recorder = ui.PictureRecorder();
    PublicationSocialCardPainter(this)
        .paint(Canvas(recorder), const Size(width, height));
    final image =
        await recorder.endRecording().toImage(width.toInt(), height.toInt());
    try {
      return await publicationJpeg(image);
    } finally {
      image.dispose();
    }
  }
}

class PublicationSocialCardPainter extends CustomPainter {
  PublicationSocialCardPainter(this.card);

  final PublicationSocialCard card;

  static const _font = 'Wavehaus';
  static const _fontPackage = 'ardrive_ui';
  static const _pad = 72.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / PublicationSocialCard.width);
    const area = Rect.fromLTWH(
        0, 0, PublicationSocialCard.width, PublicationSocialCard.height);
    canvas.clipRect(area);
    _background(canvas, area);
    _foreground(canvas);
    canvas.restore();
  }

  void _background(Canvas canvas, Rect area) {
    final cover = card.cover;
    if (cover != null) {
      paintCovering(canvas, cover, area);
      // Text sits on the lower half: darken it enough to read on any photo.
      canvas.drawRect(
        area,
        Paint()
          ..shader = ui.Gradient.linear(
            area.topCenter,
            area.bottomCenter,
            const [Color(0x33000000), Color(0x66000000), Color(0xE6000000)],
            const [0, 0.45, 1],
          ),
      );
      return;
    }
    final tint = card.iconTint ?? const Color(0xFF3A3A3A);
    canvas.drawRect(
      area,
      Paint()
        ..shader = ui.Gradient.linear(
          area.topLeft,
          area.bottomRight,
          [
            Color.lerp(tint, const Color(0xFF0E0E0E), 0.45)!,
            const Color(0xFF0E0E0E),
          ],
        ),
    );
  }

  void _foreground(Canvas canvas) {
    const maxWidth = PublicationSocialCard.width - _pad * 2;
    final icon = card.icon;
    if (icon != null) {
      const box = Rect.fromLTWH(_pad, _pad, 112, 112);
      canvas.save();
      canvas.clipRRect(RRect.fromRectAndRadius(box, const Radius.circular(24)));
      paintCovering(canvas, icon, box);
      canvas.restore();
    }

    final files = _text(card.fileCount, 28, FontWeight.w500, 0xB3FFFFFF,
        maxWidth: maxWidth - 80, maxLines: 1);
    final description = card.description.trim().isEmpty
        ? null
        : _text(card.description.trim(), 32, FontWeight.w400, 0xD9FFFFFF,
            maxWidth: maxWidth, maxLines: 2);
    final title = _text(card.title.trim(), 64, FontWeight.w700, 0xFFFFFFFF,
        maxWidth: maxWidth, maxLines: 2, height: 1.1);

    // From the bottom up: the files line, the description, the title.
    final filesTop = PublicationSocialCard.height - _pad - files.height;
    var y = filesTop;
    files.paint(canvas, Offset(_pad, y));
    if (description != null) {
      y -= 28 + description.height;
      description.paint(canvas, Offset(_pad, y));
      y -= 16;
    } else {
      y -= 28;
    }
    y -= title.height;
    title.paint(canvas, Offset(_pad, y));

    const markSize = 44.0;
    final mark = card.mark;
    final markHeight = markSize * mark.height / mark.width;
    canvas.drawImageRect(
      mark,
      Offset.zero & Size(mark.width * 1.0, mark.height * 1.0),
      Rect.fromLTWH(
        PublicationSocialCard.width - _pad - markSize,
        filesTop + (files.height - markHeight) / 2,
        markSize,
        markHeight,
      ),
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  TextPainter _text(
    String text,
    double size,
    FontWeight weight,
    int color, {
    required double maxWidth,
    required int maxLines,
    double? height,
  }) =>
      TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: _font,
            package: _fontPackage,
            fontSize: size,
            fontWeight: weight,
            color: Color(color),
            height: height,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: maxLines,
        ellipsis: '…',
      )..layout(maxWidth: maxWidth);

  @override
  bool shouldRepaint(PublicationSocialCardPainter oldDelegate) =>
      oldDelegate.card.title != card.title ||
      oldDelegate.card.description != card.description ||
      oldDelegate.card.fileCount != card.fileCount ||
      oldDelegate.card.cover != card.cover ||
      oldDelegate.card.icon != card.icon ||
      oldDelegate.card.iconTint != card.iconTint;
}

/// The average colour of [image], for a background that suits an icon.
Future<Color> averageColor(ui.Image image) async {
  final small = await publicationCrop(image, 8, 8);
  final rgba = (await small.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  small.dispose();
  var r = 0, g = 0, b = 0, weight = 0;
  for (var i = 0; i < rgba.lengthInBytes; i += 4) {
    final a = rgba.getUint8(i + 3);
    r += rgba.getUint8(i) * a;
    g += rgba.getUint8(i + 1) * a;
    b += rgba.getUint8(i + 2) * a;
    weight += a;
  }
  if (weight == 0) return const Color(0xFF3A3A3A);
  return Color.fromARGB(255, r ~/ weight, g ~/ weight, b ~/ weight);
}
