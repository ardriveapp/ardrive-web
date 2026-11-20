import 'dart:math' as math;

import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// The width under which the gallery uses its phone sizes (the app's phone
/// breakpoint).
const double galleryPhoneBreakpoint = 834;

/// Row height and gap on a phone: 3 to 4 photos a row on a 390 px screen.
const double galleryPhoneRowHeight = 86;
const double galleryPhoneGap = 2;

/// The side gutter of a phone's page, which a phone gallery keeps.
const double galleryPhoneGutter = 16;

/// Whether the screen is a phone's: the screen's width, never the room a
/// gallery happens to be given (a details panel beside it narrows it).
bool galleryScreenIsPhone(BuildContext context) =>
    MediaQuery.sizeOf(context).width < galleryPhoneBreakpoint;

/// Row height and gap everywhere else, at the 1440x900 baseline.
const double galleryDesktopRowHeight = 180;

/// The tallest a desktop row grows to, on the biggest screens.
const double galleryMaxRowHeight = 480;

/// Tile size scales with the screen so the number of tiles on screen stays
/// about what it is at 1440x900, however big the screen. A row's height grows
/// with the square root of the screen's area (width and height each grow
/// with it), so a 4x bigger screen has 2x taller rows and, for photos of the
/// same shape, about as many tiles: more pixels, not more requests.
///
/// 1440x900 gives [galleryDesktopRowHeight] (180); 2560x1440 about 304;
/// 3840x2160 about 455; never under 180 or over [galleryMaxRowHeight].
/// The screen's size is used, not the gallery's, so a details panel opening
/// beside it does not resize the tiles. A phone is [galleryPhoneRowHeight].
double galleryTargetRowHeight(Size screen, {required bool isPhone}) {
  if (isPhone) return galleryPhoneRowHeight;
  const baseline = 1440.0 * 900.0;
  final scaled = galleryDesktopRowHeight *
      math.sqrt(screen.width * screen.height / baseline);
  return scaled.clamp(galleryDesktopRowHeight, galleryMaxRowHeight);
}

const double galleryDesktopGap = ArDriveSpacing.xxs;

typedef GalleryAspectRatio = double? Function(int index);
typedef GalleryTileBuilder = Widget Function(
  BuildContext context,
  int index,
  Size size,
);

/// Photos in justified rows, as [computeJustifiedLayout] lays them out.
///
/// Rows are built lazily (a [ListView]), so only the rows on screen and a
/// little around them exist, however many items there are. The layout is
/// computed once per width and item count, not per frame.
///
/// [aspectRatioOf] gives width / height for an item, or null when unknown (a
/// square is used). When ratios change without the count changing, change
/// [layoutRevision] so rows are laid out again.
///
/// The phone sizes are chosen by the screen's width (or [isPhone]), not this
/// widget's own, so a gallery beside a details panel keeps its desktop sizes.
///
/// Row height defaults by width: [galleryPhoneRowHeight] under
/// [galleryPhoneBreakpoint], [galleryDesktopRowHeight] above, unless
/// [targetRowHeight] is given (a tile size slider).
class ArDriveJustifiedGallery extends StatefulWidget {
  const ArDriveJustifiedGallery({
    super.key,
    required this.itemCount,
    required this.aspectRatioOf,
    required this.tileBuilder,
    this.targetRowHeight,
    this.gap,
    this.maxRowHeight,
    this.padding = EdgeInsets.zero,
    this.controller,
    this.layoutRevision = 0,
    this.itemKeyOf,
    this.isPhone,
  });

  /// Whether to use the phone sizes. Defaults to the screen's width (see
  /// [galleryScreenIsPhone]), not this widget's own.
  final bool? isPhone;

  final int itemCount;
  final GalleryAspectRatio aspectRatioOf;
  final GalleryTileBuilder tileBuilder;
  final double? targetRowHeight;
  final double? gap;
  final double? maxRowHeight;
  final EdgeInsets padding;
  final ScrollController? controller;
  final Object layoutRevision;

  /// A key that identifies the item at [index] (its file id). Without it
  /// tiles are keyed by index, so after a delete or a re-sort a tile can
  /// keep the previous file's state, such as its image. Pass it.
  final Key Function(int index)? itemKeyOf;

  @override
  State<ArDriveJustifiedGallery> createState() =>
      _ArDriveJustifiedGalleryState();
}

class _ArDriveJustifiedGalleryState extends State<ArDriveJustifiedGallery> {
  List<JustifiedRow> _rows = const [];
  Object? _key;

  List<JustifiedRow> _layout(double width, double target, double gap) {
    final key = Object.hash(
      width,
      target,
      gap,
      widget.maxRowHeight,
      widget.itemCount,
      widget.layoutRevision,
    );
    if (_key != key) {
      _key = key;
      _rows = computeJustifiedLayout(
        aspectRatios: [
          for (var i = 0; i < widget.itemCount; i++) widget.aspectRatioOf(i),
        ],
        availableWidth: width,
        targetRowHeight: target,
        gap: gap,
        maxRowHeight: widget.maxRowHeight,
      );
    }
    return _rows;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final phone = widget.isPhone ?? galleryScreenIsPhone(context);
      final target = widget.targetRowHeight ??
          galleryTargetRowHeight(MediaQuery.sizeOf(context), isPhone: phone);
      final width = constraints.maxWidth - widget.padding.horizontal;
      final gap = sanitizeGap(
        widget.gap ?? (phone ? galleryPhoneGap : galleryDesktopGap),
        width,
      );
      final rows = _layout(width, target, gap);

      return ListView.builder(
        controller: widget.controller,
        padding: widget.padding,
        itemCount: rows.length,
        itemBuilder: (context, rowIndex) {
          final row = rows[rowIndex];
          return Padding(
            padding:
                EdgeInsets.only(bottom: rowIndex == rows.length - 1 ? 0 : gap),
            child: SizedBox(
              height: row.height,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < row.items.length; i++) ...[
                    if (i > 0) SizedBox(width: gap),
                    SizedBox(
                      width: row.items[i].width,
                      height: row.items[i].height,
                      child: KeyedSubtree(
                        key: widget.itemKeyOf?.call(row.items[i].index) ??
                            ValueKey(row.items[i].index),
                        child: widget.tileBuilder(
                          context,
                          row.items[i].index,
                          Size(row.items[i].width, row.items[i].height),
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
