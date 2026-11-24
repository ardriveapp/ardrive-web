import 'package:ardrive/drive_explorer/thumbnail/missing_thumbnails.dart';
import 'package:ardrive/entities/file_entity.dart';
import 'package:flutter_test/flutter_test.dart';

Variant v(int w, int h) =>
    Variant(name: 'x', txId: 't$w', size: 1000, width: w, height: h);

const photo = 3 * 1024 * 1024;

void main() {
  test('an image with no thumbnail lacks all of them, whatever its size', () {
    expect(
        missingThumbnailsOf(
            contentType: 'image/jpeg', size: 10, variants: null),
        MissingThumbnails.all);
    expect(
        missingThumbnailsOf(
            contentType: 'image/png', size: photo, variants: const []),
        MissingThumbnails.all);
  });

  test('a photo with only the small one lacks the large one', () {
    expect(
        missingThumbnailsOf(
            contentType: 'image/jpeg', size: photo, variants: [v(100, 66)]),
        MissingThumbnails.large);
    // A tall small one is still small.
    expect(
        missingThumbnailsOf(
            contentType: 'image/jpeg', size: photo, variants: [v(100, 266)]),
        MissingThumbnails.large);
  });

  test('a photo with a large one lacks nothing, in either orientation', () {
    expect(
        missingThumbnailsOf(
            contentType: 'image/jpeg',
            size: photo,
            variants: [v(100, 66), v(512, 341)]),
        MissingThumbnails.none);
    expect(
        missingThumbnailsOf(
            contentType: 'image/jpeg',
            size: photo,
            variants: [v(100, 266), v(192, 512)]),
        MissingThumbnails.none);
  });

  test('a small image is never offered a large one', () {
    expect(
        missingThumbnailsOf(
            contentType: 'image/png',
            size: largeThumbnailMinFileBytes - 1,
            variants: [v(100, 100)]),
        MissingThumbnails.none);
  });

  test('anything thumbnails are not made for lacks nothing', () {
    for (final type in [
      'application/pdf',
      'video/mp4',
      'image/svg+xml',
      null
    ]) {
      expect(
          missingThumbnailsOf(contentType: type, size: photo, variants: null),
          MissingThumbnails.none,
          reason: '$type');
    }
  });
}
