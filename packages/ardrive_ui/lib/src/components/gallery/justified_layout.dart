import 'dart:math' as math;

/// One tile in a [JustifiedRow]: the index of the item it shows and the box
/// it fills, in logical pixels.
class JustifiedItem {
  const JustifiedItem(this.index, this.width, this.height);

  final int index;
  final double width;
  final double height;

  @override
  bool operator ==(Object other) =>
      other is JustifiedItem &&
      other.index == index &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(index, width, height);

  @override
  String toString() => 'JustifiedItem($index, ${width}x$height)';
}

/// One row of a justified layout. [items] sit left to right separated by the
/// layout's gap.
class JustifiedRow {
  const JustifiedRow(this.items, this.height);

  final List<JustifiedItem> items;
  final double height;

  /// The width the row takes, gaps included.
  double widthWith(double gap) =>
      items.fold<double>(0, (sum, item) => sum + item.width) +
      gap * math.max(0, items.length - 1);
}

/// The aspect ratio range a photo is laid out with. A panorama or a
/// screenshot of a long page would otherwise become a sliver or take a whole
/// row.
const double justifiedMinAspectRatio = 0.25;
const double justifiedMaxAspectRatio = 4;

/// Turns a raw width / height into one safe to lay out: missing, zero,
/// negative or not-a-number become 1 (square), the rest is clamped to
/// [justifiedMinAspectRatio]..[justifiedMaxAspectRatio].
/// The gap a layout uses: whole pixels, never negative or not-a-number, and
/// never more than an eighth of [availableWidth], so a silly gap cannot eat
/// the row. The widget lays tiles out with this same value.
double sanitizeGap(double gap, double availableWidth) {
  if (!gap.isFinite || gap <= 0 || !availableWidth.isFinite) return 0;
  return math.min(gap.floorToDouble(), (availableWidth / 8).floorToDouble());
}

double sanitizeAspectRatio(double? aspectRatio) {
  if (aspectRatio == null || !aspectRatio.isFinite || aspectRatio <= 0) {
    return 1;
  }
  return aspectRatio.clamp(justifiedMinAspectRatio, justifiedMaxAspectRatio);
}

/// Lays items out in rows of equal height that fill [availableWidth]
/// exactly, as photo galleries do.
///
/// - [aspectRatios] are width / height per item, in order. Missing (null),
///   zero or extreme values are sanitized, see [sanitizeAspectRatio].
/// - Rows are scaled to fill the width, so no row is taller than the
///   [targetRowHeight] except through rounding, and never taller than
///   [maxRowHeight].
/// - The last row is not stretched: it stays at [targetRowHeight], left
///   aligned, unless it happens to be full.
/// - [gap] is floored to whole pixels (see [sanitizeGap]) and [availableWidth]
///   too, so every edge falls on a pixel.
/// - Widths are whole pixels and sum, with the gaps, to exactly
///   [availableWidth] in every filled row, so there are no 1 px seams.
/// - An item is never wider than the available width, so a very narrow
///   viewport gets one item per row, scaled down.
///
/// Pure, O(n); cheap enough to run for thousands of items on a resize.
List<JustifiedRow> computeJustifiedLayout({
  required List<double?> aspectRatios,
  required double availableWidth,
  required double targetRowHeight,
  double gap = 0,
  double? maxRowHeight,
}) {
  if (aspectRatios.isEmpty ||
      !availableWidth.isFinite ||
      availableWidth < 1 ||
      !targetRowHeight.isFinite ||
      targetRowHeight <= 0) {
    return const [];
  }
  final width = availableWidth.floorToDouble();
  final safeGap = sanitizeGap(gap, width);
  final target = targetRowHeight;
  final cap = math.max(maxRowHeight ?? target * 1.5, target);

  final ratios = [for (final r in aspectRatios) sanitizeAspectRatio(r)];
  final rows = <JustifiedRow>[];

  // Height a row of items [from, to) would have if stretched to the width.
  double fitHeight(double ratioSum, int count) =>
      (width - safeGap * (count - 1)) / ratioSum;

  var start = 0;
  while (start < ratios.length) {
    var end = start;
    var sum = 0.0;
    while (end < ratios.length) {
      // Another item needs at least 1 px; if the gaps leave none, close the
      // row here, whatever its height.
      if (end > start && width - safeGap * (end - start) < (end - start + 1)) {
        break;
      }
      sum += ratios[end];
      end++;
      if (fitHeight(sum, end - start) <= target) break;
    }

    final count = end - start;
    final h = fitHeight(sum, count);
    if (h > target && end == ratios.length) {
      // Ran out of items before the row filled: the last row, left at the
      // target height. Its width is at most the available width.
      rows.add(_row(ratios, start, end, target, width, safeGap, fill: false));
      break;
    }

    // The row is full and at or under the target. Dropping its last item
    // makes a taller row; do it when that sits closer to the target, as long
    // as it stays under the cap.
    if (count > 1) {
      final without = fitHeight(sum - ratios[end - 1], count - 1);
      if (without <= cap && (without - target) < (target - h)) {
        end--;
        sum -= ratios[end];
      }
    }

    final rowHeight = fitHeight(sum, end - start);
    rows.add(_row(
      ratios,
      start,
      end,
      math.min(rowHeight, cap),
      width,
      safeGap,
      fill: rowHeight <= cap,
    ));
    start = end;
  }
  return rows;
}

JustifiedRow _row(
  List<double> ratios,
  int start,
  int end,
  double height,
  double width,
  double gap, {
  required bool fill,
}) {
  final count = end - start;
  final rowHeight = math.max(1.0, height.roundToDouble());
  final items = <JustifiedItem>[];
  var sum = 0.0;
  for (var i = start; i < end; i++) {
    sum += ratios[i];
  }
  final usable = width - gap * (count - 1); // whole: width and gap are
  var x = 0.0; // exact running edge, before rounding
  var roundedEdge = 0.0;
  for (var i = start; i < end; i++) {
    final exact = fill ? usable * ratios[i] / sum : rowHeight * ratios[i];
    x += exact;
    // Cumulative rounding: each edge is rounded once, so the rounding error
    // of one tile goes to its neighbour and the row ends exactly on width.
    // (usable is a whole number, so a filled row's last edge is exactly it.)
    var edge = x.roundToDouble();
    // An unfilled row is sized from its rounded height, which can come out a
    // pixel or two wider than the space: never wider than what is left.
    edge = math.min(edge, usable);
    final w = math.max(1.0, edge - roundedEdge);
    items.add(JustifiedItem(i, w, rowHeight));
    roundedEdge = edge;
  }
  return JustifiedRow(items, rowHeight);
}
