import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tiles in the rows that start on screen, for a long folder of [ratio]
/// photos on a [screen], laid out as the gallery does (its width less the
/// timeline's room).
int visibleTiles(Size screen, double ratio) {
  final rowHeight = galleryTargetRowHeight(screen, isPhone: false);
  final rows = computeJustifiedLayout(
    aspectRatios: List.filled(2000, ratio),
    availableWidth: screen.width - ArDriveGalleryScrubber.defaultWidth,
    targetRowHeight: rowHeight,
    gap: galleryDesktopGap,
  );
  var top = 0.0, count = 0;
  for (final row in rows) {
    if (top >= screen.height) break;
    count += row.items.length;
    top += row.height + galleryDesktopGap;
  }
  return count;
}

void main() {
  const baseline = Size(1440, 900);
  const qhd = Size(2560, 1440);
  const uhd = Size(3840, 2160);

  test('1440x900 is the 180 px baseline; phones are 86', () {
    expect(galleryTargetRowHeight(baseline, isPhone: false), 180);
    expect(galleryTargetRowHeight(const Size(390, 800), isPhone: true), 86);
  });

  test('rows grow with the screen, up to a cap, and never shrink', () {
    final hd = galleryTargetRowHeight(const Size(1920, 1080), isPhone: false);
    final q = galleryTargetRowHeight(qhd, isPhone: false);
    final u = galleryTargetRowHeight(uhd, isPhone: false);
    expect(hd, greaterThan(180));
    expect(q, greaterThan(hd));
    expect(u, greaterThan(q));
    expect(galleryTargetRowHeight(const Size(1000, 600), isPhone: false), 180);
    expect(galleryTargetRowHeight(const Size(20000, 20000), isPhone: false),
        galleryMaxRowHeight);
  });

  for (final entry in {'3:2': 1.5, '4:3': 4 / 3, '2:3': 2 / 3}.entries) {
    test('${entry.key} photos: tiles on screen stay bounded on any screen', () {
      final base = visibleTiles(baseline, entry.value);
      for (final screen in [const Size(1920, 1080), qhd, uhd]) {
        final n = visibleTiles(screen, entry.value);
        // About the baseline's count, and never a hundred.
        expect(n, lessThanOrEqualTo(base * 1.5), reason: '$screen');
        expect(n, lessThanOrEqualTo(80), reason: '$screen');
      }
      expect(base, lessThanOrEqualTo(80));
    });
  }
}
