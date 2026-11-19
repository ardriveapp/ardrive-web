import 'dart:math' as math;

import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// Height of a section's header line.
const double galleryHeaderHeight = 44;

/// Room left under the last row of a section, before the next header.
const double gallerySectionSpacing = ArDriveSpacing.md;

/// One run of tiles in an [ArDriveSectionedGallery]: a month, or the
/// folders. Items are numbered across all sections, in order.
class ArDriveGallerySection {
  const ArDriveGallerySection({
    required this.key,
    required this.itemCount,
    this.header,
    this.targetRowHeight,
    this.gap,
  });

  /// Identifies the section (a month) between rebuilds.
  final Object key;
  final int itemCount;

  /// Shown above the section's rows, [galleryHeaderHeight] tall.
  final Widget? header;

  /// Overrides the default row height, such as for a row of folders.
  final double? targetRowHeight;
  final double? gap;
}

/// Where one row of tiles sits, in scroll coordinates.
class GalleryRowGeometry {
  const GalleryRowGeometry({
    required this.section,
    required this.top,
    required this.height,
    required this.items,
    required this.lefts,
  });

  final int section;
  final double top;
  final double height;

  /// Items with their gallery-wide index.
  final List<JustifiedItem> items;

  /// Each item's left edge within the row.
  final List<double> lefts;

  int get first => items.first.index;
  int get last => items.last.index;
  double centerOf(int position) => lefts[position] + items[position].width / 2;
}

enum GalleryDirection { left, right, up, down }

/// The whole gallery laid out: every row's place and every section's offset.
/// Pure, so keyboard movement and the timeline are tested without a widget.
class ArDriveGalleryGeometry {
  ArDriveGalleryGeometry._({
    required this.rows,
    required this.sectionOffsets,
    required this.contentHeight,
    required this.itemCount,
    required this.lines,
  });

  final List<GalleryRowGeometry> rows;

  /// The scroll offset of each section's top (its header, when it has one).
  final List<double> sectionOffsets;
  final double contentHeight;
  final int itemCount;

  /// What the list builds: header lines and row lines, in order.
  final List<GalleryLine> lines;

  /// Lays [sections] out in [width], tiles sized by [aspectRatioOf] (gallery
  /// wide index).
  static ArDriveGalleryGeometry compute({
    required List<ArDriveGallerySection> sections,
    required double Function(int index) aspectRatioOf,
    required double width,
    required double defaultRowHeight,
    required double defaultGap,
    double paddingTop = 0,
  }) {
    final rows = <GalleryRowGeometry>[];
    final lines = <GalleryLine>[];
    final offsets = <double>[];
    var y = paddingTop;
    var firstIndex = 0;

    for (var s = 0; s < sections.length; s++) {
      final section = sections[s];
      offsets.add(y);
      if (section.header != null) {
        lines.add(GalleryLine.header(s, y, galleryHeaderHeight));
        y += galleryHeaderHeight;
      }
      final gap = sanitizeGap(section.gap ?? defaultGap, width);
      final laid = computeJustifiedLayout(
        aspectRatios: [
          for (var i = 0; i < section.itemCount; i++)
            aspectRatioOf(firstIndex + i),
        ],
        availableWidth: width,
        targetRowHeight: section.targetRowHeight ?? defaultRowHeight,
        gap: gap,
      );
      for (var r = 0; r < laid.length; r++) {
        final row = laid[r];
        final items = [
          for (final item in row.items)
            JustifiedItem(firstIndex + item.index, item.width, item.height),
        ];
        var left = 0.0;
        final lefts = <double>[];
        for (final item in items) {
          lefts.add(left);
          left += item.width + gap;
        }
        final last = r == laid.length - 1;
        final lineHeight = row.height + (last ? gallerySectionSpacing : gap);
        rows.add(GalleryRowGeometry(
          section: s,
          top: y,
          height: row.height,
          items: items,
          lefts: lefts,
        ));
        lines.add(GalleryLine.row(s, rows.length - 1, y, lineHeight, gap));
        y += lineHeight;
      }
      firstIndex += section.itemCount;
    }

    return ArDriveGalleryGeometry._(
      rows: rows,
      sectionOffsets: offsets,
      contentHeight: y,
      itemCount: firstIndex,
      lines: lines,
    );
  }

  /// The row holding [index], or null.
  int? rowOf(int index) {
    var lo = 0, hi = rows.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      final row = rows[mid];
      if (index < row.first) {
        hi = mid - 1;
      } else if (index > row.last) {
        lo = mid + 1;
      } else {
        return mid;
      }
    }
    return null;
  }

  /// The section whose top is at or above [offset].
  int sectionAt(double offset) {
    var found = 0;
    for (var i = 0; i < sectionOffsets.length; i++) {
      if (sectionOffsets[i] <= offset + 1) found = i;
    }
    return found;
  }

  /// The tile to move to from [index], or null when there is none that way.
  /// Left and right follow the order; up and down stay as near as they can to
  /// the same place across, in the row above or below, whatever its section.
  int? neighbour(int index, GalleryDirection direction) {
    switch (direction) {
      case GalleryDirection.left:
        return index > 0 ? index - 1 : null;
      case GalleryDirection.right:
        return index < itemCount - 1 ? index + 1 : null;
      case GalleryDirection.up:
      case GalleryDirection.down:
        final r = rowOf(index);
        if (r == null) return null;
        final target = r + (direction == GalleryDirection.down ? 1 : -1);
        if (target < 0 || target >= rows.length) return null;
        final from = rows[r];
        final position = index - from.first;
        final x = from.centerOf(position);
        final row = rows[target];
        var best = 0;
        var bestDistance = double.infinity;
        for (var i = 0; i < row.items.length; i++) {
          final d = (row.centerOf(i) - x).abs();
          if (d < bestDistance) {
            bestDistance = d;
            best = i;
          }
        }
        return row.items[best].index;
    }
  }
}

/// One line of the gallery's list: a section's header, or one of its rows.
class GalleryLine {
  const GalleryLine.header(this.section, this.top, this.extent)
      : row = null,
        gap = 0;
  const GalleryLine.row(
      this.section, int this.row, this.top, this.extent, this.gap);

  final int section;
  final int? row;
  final double top;
  final double extent;
  final double gap;
}

/// Drives an [ArDriveSectionedGallery]: its scroll, and where everything is
/// once laid out, for the timeline and for moving between tiles.
class ArDriveSectionedGalleryController extends ChangeNotifier {
  ArDriveSectionedGalleryController({ScrollController? scroll})
      : scroll = scroll ?? ScrollController(),
        _ownsScroll = scroll == null;

  final ScrollController scroll;
  final bool _ownsScroll;
  ArDriveGalleryGeometry? _geometry;

  ArDriveGalleryGeometry? get geometry => _geometry;

  void setGeometry(ArDriveGalleryGeometry geometry) {
    if (identical(_geometry, geometry)) return;
    _geometry = geometry;
    notifyListeners();
  }

  /// Scrolls just enough for the row holding [index] to be on screen.
  void ensureVisible(int index) {
    final geometry = _geometry;
    if (geometry == null || !scroll.hasClients) return;
    final r = geometry.rowOf(index);
    if (r == null) return;
    final row = geometry.rows[r];
    final position = scroll.position;
    final top = row.top;
    final bottom = row.top + row.height;
    final viewTop = position.pixels;
    final viewBottom = viewTop + position.viewportDimension;
    double? target;
    if (top < viewTop) {
      target = top - ArDriveSpacing.sm;
    } else if (bottom > viewBottom) {
      target = bottom - position.viewportDimension + ArDriveSpacing.sm;
    }
    if (target != null) {
      scroll.jumpTo(target.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ));
    }
  }

  void jumpToSection(int section) {
    final geometry = _geometry;
    if (geometry == null || !scroll.hasClients) return;
    if (section < 0 || section >= geometry.sectionOffsets.length) return;
    final position = scroll.position;
    // Not clamped to the list's extent: until every row is built that is an
    // estimate, and a short one would stop the jump before the month. The
    // list corrects an offset past its real end when it lays out.
    scroll.jumpTo(
        math.max(position.minScrollExtent, geometry.sectionOffsets[section]));
  }

  @override
  void dispose() {
    if (_ownsScroll) scroll.dispose();
    super.dispose();
  }
}

typedef GallerySectionTileBuilder = Widget Function(
  BuildContext context,
  int index,
  Size size,
);

/// Photos in justified rows, in sections with headers: the months of a
/// folder. Like [ArDriveJustifiedGallery], rows are built lazily, so only
/// what is on screen exists; unlike it, it knows where everything is, which
/// the timeline and arrow-key movement need ([ArDriveSectionedGalleryController]).
class ArDriveSectionedGallery extends StatefulWidget {
  const ArDriveSectionedGallery({
    super.key,
    required this.controller,
    required this.sections,
    required this.aspectRatioOf,
    required this.tileBuilder,
    this.itemKeyOf,
    this.padding = EdgeInsets.zero,
    this.layoutRevision = 0,
    this.targetRowHeight,
    this.isPhone,
  });

  /// Defaults to the screen's width, see [galleryScreenIsPhone].
  final bool? isPhone;

  final ArDriveSectionedGalleryController controller;
  final List<ArDriveGallerySection> sections;

  /// width / height for the item at a gallery-wide index, or null if unknown.
  final double? Function(int index) aspectRatioOf;
  final GallerySectionTileBuilder tileBuilder;
  final Key Function(int index)? itemKeyOf;
  final EdgeInsets padding;

  /// Change when ratios or the order change without the counts changing.
  final Object layoutRevision;
  final double? targetRowHeight;

  @override
  State<ArDriveSectionedGallery> createState() =>
      _ArDriveSectionedGalleryState();
}

class _ArDriveSectionedGalleryState extends State<ArDriveSectionedGallery> {
  ArDriveGalleryGeometry? _geometry;
  Object? _key;

  ArDriveGalleryGeometry _layout(double width, double target, double gap) {
    final key = Object.hash(
      width,
      target,
      gap,
      widget.layoutRevision,
      widget.padding.top,
      Object.hashAll([
        for (final s in widget.sections)
          Object.hash(
              s.key, s.itemCount, s.targetRowHeight, s.gap, s.header != null),
      ]),
    );
    if (_key != key || _geometry == null) {
      _key = key;
      _geometry = ArDriveGalleryGeometry.compute(
        sections: widget.sections,
        aspectRatioOf: (i) => widget.aspectRatioOf(i) ?? 1,
        width: width,
        defaultRowHeight: target,
        defaultGap: gap,
        paddingTop: widget.padding.top,
      );
      final geometry = _geometry!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(_geometry, geometry)) {
          widget.controller.setGeometry(geometry);
        }
      });
    }
    return _geometry!;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final phone = widget.isPhone ?? galleryScreenIsPhone(context);
      final target = widget.targetRowHeight ??
          galleryTargetRowHeight(MediaQuery.sizeOf(context), isPhone: phone);
      final width =
          math.max(1.0, constraints.maxWidth - widget.padding.horizontal);
      final gap = phone ? galleryPhoneGap : galleryDesktopGap;
      final geometry = _layout(width, target, gap);

      return ListView.builder(
        controller: widget.controller.scroll,
        padding: widget.padding,
        // A little past the screen, so the next row is already built; what
        // loads is decided by the tiles, not by this.
        cacheExtent: 400,
        itemCount: geometry.lines.length,
        itemBuilder: (context, i) {
          final line = geometry.lines[i];
          final row = line.row;
          if (row == null) {
            final header = widget.sections[line.section].header!;
            return SizedBox(
              key: ValueKey(
                  'gallery-header-${widget.sections[line.section].key}'),
              height: line.extent,
              child: header,
            );
          }
          final g = geometry.rows[row];
          return Padding(
            padding: EdgeInsets.only(bottom: line.extent - g.height),
            child: SizedBox(
              height: g.height,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var k = 0; k < g.items.length; k++) ...[
                    if (k > 0) SizedBox(width: line.gap),
                    SizedBox(
                      width: g.items[k].width,
                      height: g.items[k].height,
                      child: KeyedSubtree(
                        key: widget.itemKeyOf?.call(g.items[k].index) ??
                            ValueKey(g.items[k].index),
                        child: widget.tileBuilder(
                          context,
                          g.items[k].index,
                          Size(g.items[k].width, g.items[k].height),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      );
    });
  }
}
