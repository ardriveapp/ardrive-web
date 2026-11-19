import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// The width under which the gallery uses its phone sizes (the app's phone
/// breakpoint).
const double galleryPhoneBreakpoint = 834;

/// Row height and gap on a phone: 3 to 4 photos a row on a 390 px screen.
const double galleryPhoneRowHeight = 86;
const double galleryPhoneGap = 2;

/// Row height and gap everywhere else.
const double galleryDesktopRowHeight = 180;
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
/// The phone sizes are chosen by this widget's own width, not the screen's,
/// so a gallery in a narrow panel gets them too.
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
  });

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
      final phone = constraints.maxWidth < galleryPhoneBreakpoint;
      final target = widget.targetRowHeight ??
          (phone ? galleryPhoneRowHeight : galleryDesktopRowHeight);
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
