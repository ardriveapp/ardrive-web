import 'package:ardrive/publication/presentation/publication_header_fold.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PublicationHeaderFold', () {
    test('a short list that fits once folded stays folded', () {
      // Unfolded, the list has 60px more to show; folded, it fits.
      final fold = PublicationHeaderFold();
      fold.onScroll(pixels: 0, maxScrollExtent: 60, moved: false);

      expect(fold.onWheel(40), isTrue, reason: 'the wheel folds it');
      expect(
          fold.onScroll(pixels: 40, maxScrollExtent: 60, moved: true), isFalse);
      expect(fold.folded, isTrue);

      // The fold makes the list fit, and Flutter moves it back to its top.
      fold.onScroll(pixels: 40, maxScrollExtent: 0, moved: false);
      for (final pixels in [25.0, 10.0, 0.0]) {
        fold.onScroll(pixels: pixels, maxScrollExtent: 0, moved: true);
      }
      expect(fold.folded, isTrue,
          reason: 'that move was not the user\'s, so it must not unfold');

      // More wheel down changes nothing.
      expect(fold.onWheel(40), isFalse);
      expect(fold.folded, isTrue);

      // The wheel turned up at the top unfolds it.
      expect(fold.onWheel(-40), isTrue);
      expect(fold.folded, isFalse);
    });

    test('a long list folds as it scrolls and unfolds back at its top', () {
      final fold = PublicationHeaderFold();
      fold.onScroll(pixels: 0, maxScrollExtent: 2000, moved: false);
      fold.onScroll(pixels: 120, maxScrollExtent: 2000, moved: true);
      expect(fold.folded, isTrue);
      fold.onScroll(pixels: 120, maxScrollExtent: 1800, moved: false);
      expect(fold.folded, isTrue);
      fold.onScroll(pixels: 0, maxScrollExtent: 1800, moved: true);
      expect(fold.folded, isFalse, reason: 'the user scrolled back up');
    });

    test('a list that fits even unfolded never folds', () {
      final fold = PublicationHeaderFold();
      fold.onScroll(pixels: 0, maxScrollExtent: 0, moved: false);
      expect(fold.onWheel(40), isFalse);
      expect(fold.onSwipe(-800), isFalse);
      expect(fold.folded, isFalse);
    });

    test('a swipe folds and unfolds on a phone', () {
      final fold = PublicationHeaderFold();
      fold.onScroll(pixels: 0, maxScrollExtent: 60, moved: false);
      expect(fold.onSwipe(-800), isTrue);
      fold.onScroll(pixels: 0, maxScrollExtent: 0, moved: false);
      expect(fold.onSwipe(800), isTrue);
      expect(fold.folded, isFalse);
    });

    test('a folder newly shown starts unfolded', () {
      final fold = PublicationHeaderFold();
      fold.onScroll(pixels: 50, maxScrollExtent: 500, moved: true);
      expect(fold.folded, isTrue);
      fold.reset();
      expect(fold.folded, isFalse);
    });
  });
}
