import 'dart:math';

import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<JustifiedRow> layout(
    List<double?> ratios, {
    double width = 1000,
    double target = 180,
    double gap = 4,
    double? max,
  }) =>
      computeJustifiedLayout(
        aspectRatios: ratios,
        availableWidth: width,
        targetRowHeight: target,
        gap: gap,
        maxRowHeight: max,
      );

  final rng = Random(7);
  final mixed = [for (var i = 0; i < 500; i++) 0.4 + rng.nextDouble() * 2.4];

  test('empty and unusable input gives no rows', () {
    expect(layout([]), isEmpty);
    expect(layout([1], width: 0), isEmpty);
    expect(layout([1], width: double.nan), isEmpty);
    expect(layout([1], target: 0), isEmpty);
  });

  test('every item appears exactly once, in order', () {
    final rows = layout(mixed);
    final indexes = [for (final r in rows) ...r.items.map((i) => i.index)];
    expect(indexes, List.generate(mixed.length, (i) => i));
  });

  test('filled rows span the width exactly, whatever the width', () {
    for (final w in [300.0, 389.0, 390.0, 777.0, 1000.0, 1333.0, 2561.0]) {
      final rows = layout(mixed, width: w, gap: 2);
      for (final row in rows.take(rows.length - 1)) {
        expect(row.widthWith(2), w, reason: 'width $w');
      }
    }
  });

  test('widths and heights are whole pixels', () {
    for (final row in layout(mixed)) {
      expect(row.height, row.height.roundToDouble());
      for (final i in row.items) {
        expect(i.width, i.width.roundToDouble());
        expect(i.height, row.height);
      }
    }
  });

  test('no row is taller than the cap, none shorter than needed', () {
    final rows = layout(mixed, max: 220);
    for (final r in rows) {
      expect(r.height, lessThanOrEqualTo(220));
      expect(r.height, greaterThan(0));
    }
    // Default cap is 1.5x the target.
    for (final r in layout(mixed)) {
      expect(r.height, lessThanOrEqualTo(270));
    }
  });

  test('a cap below the target is raised to the target', () {
    for (final r in layout(mixed, max: 10)) {
      expect(r.height, lessThanOrEqualTo(180));
    }
  });

  test('the last row is left aligned at the target, not stretched', () {
    final rows = layout([1, 1], width: 1000);
    expect(rows, hasLength(1));
    expect(rows.single.height, 180);
    expect(rows.single.items.map((i) => i.width), [180, 180]);
    expect(rows.single.widthWith(4), lessThan(1000));
  });

  test('a lone item is at the target height', () {
    final rows = layout([1.5]);
    expect(rows.single.items.single.width, 270);
    expect(rows.single.height, 180);
  });

  test('a lone wide item is scaled down to the width', () {
    final rows = layout([4], width: 200);
    final item = rows.single.items.single;
    expect(item.width, lessThanOrEqualTo(200));
    expect(rows.single.height, 50);
  });

  test('rows other than the last are not taller than the target', () {
    final rows = layout(mixed);
    for (final r in rows.take(rows.length - 1)) {
      // The drop rule can make a row a little taller than the target.
      expect(r.height, lessThanOrEqualTo(270));
    }
    final mean = rows
            .take(rows.length - 1)
            .map((r) => r.height)
            .reduce((a, b) => a + b) /
        (rows.length - 1);
    expect(mean, closeTo(180, 25));
  });

  test('aspect ratio is kept close to the item', () {
    final rows = layout(mixed);
    for (final r in rows.take(rows.length - 1)) {
      for (final i in r.items) {
        final want = mixed[i.index];
        expect((i.width / i.height) / want, closeTo(1, 0.1));
      }
    }
  });

  test('missing, zero, negative and NaN ratios are treated as square', () {
    final a = layout([null, 0, -2, double.nan, double.infinity, 1]);
    final b = layout([1, 1, 1, 1, 1, 1]);
    List<String> flat(List<JustifiedRow> rows) =>
        [for (final r in rows) ...r.items.map((i) => '$i')];
    expect(flat(a), flat(b));
  });

  test('extreme ratios are clamped to 0.25..4', () {
    expect(sanitizeAspectRatio(100), 4);
    expect(sanitizeAspectRatio(0.001), 0.25);
    expect(sanitizeAspectRatio(1.5), 1.5);
    final rows = layout([1000, 0.0001], width: 1000);
    for (final r in rows) {
      for (final i in r.items) {
        expect(i.width / i.height, inInclusiveRange(0.2, 4.1));
      }
    }
  });

  test('phone: 390 wide, 86 target, 2 px gap gives 3 to 4 square photos', () {
    final rows = layout(List.filled(40, 1.0), width: 390, target: 86, gap: 2);
    for (final r in rows.take(rows.length - 1)) {
      expect(r.items.length, inInclusiveRange(3, 5));
      expect(r.widthWith(2), 390);
      expect(r.height, inInclusiveRange(70, 129));
    }
  });

  test('very narrow widths give one item per row, never overflowing', () {
    for (final w in [1.0, 20.0, 60.0]) {
      final rows = layout([1, 0.25, 4, 1.7], width: w, target: 86, gap: 2);
      expect(rows, isNotEmpty);
      for (final r in rows) {
        expect(r.widthWith(2), lessThanOrEqualTo(w));
        for (final i in r.items) {
          expect(i.width, greaterThanOrEqualTo(1));
          expect(i.height, greaterThanOrEqualTo(1));
        }
      }
    }
  });

  test('zero gap works and fills exactly', () {
    final rows = layout(mixed, gap: 0, width: 913);
    for (final r in rows.take(rows.length - 1)) {
      expect(r.widthWith(0), 913);
    }
  });

  test('a fractional available width is floored', () {
    final rows = layout(mixed, width: 500.9);
    expect(rows.first.widthWith(4), 500);
  });

  List<List<int>> shape(List<JustifiedRow> rows) => [
        for (final r in rows) [for (final i in r.items) i.index]
      ];

  group('the drop-last-item rule', () {
    // Target 100, width 1000, no gap, cap 150. Three ratio-3 photos need
    // 111 px to fill the row; a ratio-4 fourth would make it 77, which is
    // further from 100 than 111 is, so the fourth goes to the next row.
    test('drops the item when that is closer to the target', () {
      final rows = layout([3, 3, 3, 4, 1], target: 100, gap: 0);
      expect(shape(rows), [
        [0, 1, 2],
        [3, 4]
      ]);
      expect(rows.first.height, 111);
      expect(rows.first.items.map((i) => i.width), [333, 334, 333]);
      expect(rows.last.height, 100);
    });

    test('keeps the item when dropping would pass the cap', () {
      final rows = layout([3, 3, 3, 4, 1], target: 100, gap: 0, max: 105);
      expect(shape(rows), [
        [0, 1, 2, 3],
        [4]
      ]);
      expect(rows.first.height, 77);
    });

    test('keeps the item when it is the closer fit', () {
      // 9 + 1.2 = 10.2 fills at 98 px; without it 111 is further away.
      final rows = layout([3, 3, 3, 1.2, 1], target: 100, gap: 0);
      expect(shape(rows), [
        [0, 1, 2, 3],
        [4]
      ]);
      expect(rows.first.height, 98);
    });

    test('keeps the item when it is only a little further than dropping', () {
      // 9 + 2 = 11 fills at 91 px (9 under); without it 111 is 11 over.
      final rows = layout([3, 3, 3, 2, 1], target: 100, gap: 0);
      expect(shape(rows), [
        [0, 1, 2, 3],
        [4]
      ]);
      expect(rows.first.height, 91);
    });

    test('a one-item row is never dropped', () {
      final rows = layout([4, 4], target: 100, gap: 0);
      expect(shape(rows).first, [0, 1]);
    });
  });

  group('fractional input', () {
    test('a fractional gap is floored: rows still fill exactly', () {
      final rows = layout(mixed, width: 390, target: 86.6, gap: 2.5);
      for (final r in rows.take(rows.length - 1)) {
        expect(r.widthWith(2), 390);
      }
      expect(sanitizeGap(2.5, 390), 2);
      expect(sanitizeGap(-1, 390), 0);
      expect(sanitizeGap(double.nan, 390), 0);
      expect(sanitizeGap(500, 390), 48);
    });

    test('a fractional target gives whole pixel rows', () {
      for (final r in layout(mixed, width: 390, target: 86.6, gap: 2.5)) {
        expect(r.height, r.height.roundToDouble());
        for (final i in r.items) {
          expect(i.width, i.width.roundToDouble());
        }
      }
    });

    test('an unfilled row whose rounded height overshoots stays inside', () {
      // 4 x 86.6 = 346.4 < 347, so the row is unfilled; at the rounded 87 px
      // the photo would be 348 wide, a pixel more than there is.
      final rows = layout([4], width: 347, target: 86.6, gap: 2.5);
      expect(rows.single.items.single.width, 347);
      expect(rows.single.widthWith(2), lessThanOrEqualTo(347));
    });

    test('an absurd gap cannot push a row past the width', () {
      final rows =
          layout(List.filled(30, 0.25), width: 40, target: 86, gap: 30);
      for (final r in rows) {
        expect(r.widthWith(sanitizeGap(30, 40)), lessThanOrEqualTo(40));
      }
    });
  });

  test('5000 items lay out quickly', () {
    final many = [for (var i = 0; i < 5000; i++) 0.5 + (i % 7) * 0.3];
    final sw = Stopwatch()..start();
    final rows = layout(many);
    expect(sw.elapsedMilliseconds, lessThan(200));
    expect(rows.fold<int>(0, (s, r) => s + r.items.length), 5000);
  });
}
