import 'dart:io';
import 'dart:typed_data';

import 'package:ardrive/publication/domain/publication_images.dart';
import 'package:ardrive/publication/domain/publication_social_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _photo(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (final pixel in image) {
    pixel
      ..r = (pixel.x * 255 ~/ width)
      ..g = (pixel.y * 255 ~/ height)
      ..b = ((pixel.x + pixel.y) % 256);
  }
  return img.encodePng(image);
}

void main() {
  testWidgets('an icon makes 32, 180 and 512 pixel PNGs', (tester) async {
    await tester.runAsync(() async {
      final picture = await PublicationPicture.decode(_photo(900, 600));
      final files = await publicationIconFiles(picture.image);
      expect(files.keys, ['icon-32.png', 'icon-180.png', 'icon-512.png']);
      for (final MapEntry(:key, :value) in files.entries) {
        final size = int.parse(key.split('-')[1].split('.')[0]);
        final decoded = img.decodePng(value)!;
        expect((decoded.width, decoded.height), (size, size));
      }
    });
  });

  testWidgets('a cover is cropped to 4:1 and kept under its budget',
      (tester) async {
    await tester.runAsync(() async {
      final picture = await PublicationPicture.decode(_photo(3000, 3000));
      final jpeg = await publicationBannerFile(
          picture.image, PublicationImageKind.cover);
      final decoded = img.decodeJpg(jpeg)!;
      expect((decoded.width, decoded.height), (1600, 400));
      expect(jpeg.length, lessThan(publicationJpegBudgetBytes));
    });
  });

  testWidgets('a small picture is used, and said to be small', (tester) async {
    await tester.runAsync(() async {
      final picture = await PublicationPicture.decode(_photo(800, 200));
      expect(picture.isSmallFor(PublicationImageKind.cover), isTrue);
      expect(picture.isSmallFor(PublicationImageKind.icon), isTrue);
      final big = await PublicationPicture.decode(_photo(1600, 1600));
      expect(big.isSmallFor(PublicationImageKind.cover), isFalse);
    });
  });

  testWidgets('what is not a picture, or too big, is refused', (tester) async {
    await tester.runAsync(() async {
      await expectLater(
        PublicationPicture.decode(Uint8List.fromList(List.filled(64, 7))),
        throwsA(isA<PublicationImageException>().having(
            (e) => e.reason, 'reason', PublicationImageProblem.notAnImage)),
      );
      await expectLater(
        PublicationPicture.decode(Uint8List(publicationImageMaxBytes + 1)),
        throwsA(isA<PublicationImageException>().having(
            (e) => e.reason, 'reason', PublicationImageProblem.tooLarge)),
      );
    });
  });

  testWidgets('the generated card is a 1200 × 630 JPEG under its budget',
      (tester) async {
    await tester.runAsync(() async {
      final cover = await PublicationPicture.decode(_photo(1600, 400));
      final icon = await PublicationPicture.decode(_photo(512, 512));
      final mark = await PublicationPicture.decode(
          File('assets/images/brand/1x.png').readAsBytesSync());
      for (final withCover in [true, false]) {
        final card = PublicationSocialCard(
          title: 'Publication QA drive with a title long enough to wrap twice '
              'and then be cut short',
          description: 'Photos, notes and the odd recording.',
          fileCount: '79 files',
          cover: withCover ? cover.image : null,
          icon: icon.image,
          iconTint: await averageColor(icon.image),
          mark: mark.image,
        );
        final jpeg = await card.render();
        final decoded = img.decodeJpg(jpeg)!;
        expect((decoded.width, decoded.height), (1200, 630));
        expect(jpeg.length, lessThan(publicationJpegBudgetBytes));
        final out = Platform.environment['PUBLICATION_CARD_OUT'];
        if (out != null) {
          File('$out/card-${withCover ? 'cover' : 'icon'}.jpg')
              .writeAsBytesSync(jpeg);
        }
      }
    });
  });

  testWidgets('the average colour of an icon', (tester) async {
    await tester.runAsync(() async {
      final red = img.Image(width: 4, height: 4)
        ..clear(img.ColorRgb8(200, 10, 10));
      final picture = await PublicationPicture.decode(img.encodePng(red));
      final color = await averageColor(picture.image);
      expect(color.red, closeTo(200, 2));
      expect(color.blue, closeTo(10, 2));
    });
  });

  test('kinds have the design sizes', () {
    expect(PublicationImageKind.social.aspect, closeTo(1.905, 0.01));
    expect(PublicationImageKind.cover.aspect, 4);
  });
}
