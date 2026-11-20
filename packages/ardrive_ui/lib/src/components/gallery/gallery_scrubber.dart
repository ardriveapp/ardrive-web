import 'dart:async';
import 'dart:math' as math;

import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// One stop on the timeline: a section, its name for the bubble, and a short
/// tick label (a year) where one fits.
class ArDriveGalleryScrubberEntry {
  const ArDriveGalleryScrubberEntry({
    required this.section,
    required this.title,
    this.tick,
  });

  final int section;
  final String title;
  final String? tick;
}

/// The timeline on a gallery's right edge: drag or tap to jump between
/// months. At rest on a wide screen it shows year ticks; on a phone nothing,
/// and a handle with the month while the list scrolls or the handle is held.
///
/// Shown only for a long gallery: [minScreens] viewports of content or more.
class ArDriveGalleryScrubber extends StatefulWidget {
  const ArDriveGalleryScrubber({
    super.key,
    required this.controller,
    required this.entries,
    required this.semanticLabel,
    this.minScreens = 2,
    this.width = ArDriveGalleryScrubber.defaultWidth,
  });

  final ArDriveSectionedGalleryController controller;
  final List<ArDriveGalleryScrubberEntry> entries;
  final String semanticLabel;
  final double minScreens;

  /// How wide the track is: the room a gallery keeps on its right.
  /// Wide enough for the year labels, so the whole column reacts to a hover.
  static const double defaultWidth = 64;

  /// How far back the timeline sits at rest: clear, not loud.
  static const double restOpacity = 0.7;

  /// On a phone the handle sits over the photos, so its hit area is narrower.
  static const double phoneWidth = 28;

  final double width;

  @override
  State<ArDriveGalleryScrubber> createState() => _ArDriveGalleryScrubberState();
}

class _ArDriveGalleryScrubberState extends State<ArDriveGalleryScrubber> {
  bool _dragging = false;
  bool _hovering = false;
  bool _scrolling = false;
  Timer? _rest;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    widget.controller.scroll.addListener(_scrolled);
  }

  @override
  void didUpdateWidget(ArDriveGalleryScrubber old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      old.controller.scroll.removeListener(_scrolled);
      widget.controller.addListener(_changed);
      widget.controller.scroll.addListener(_scrolled);
    }
  }

  @override
  void dispose() {
    _rest?.cancel();
    widget.controller.removeListener(_changed);
    widget.controller.scroll.removeListener(_scrolled);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _scrolled() {
    if (!mounted) return;
    _rest?.cancel();
    _rest = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _scrolling = false);
    });
    setState(() => _scrolling = true);
  }

  /// How far the content scrolls, from where the rows were laid out. The
  /// list's own extent is an estimate until every row has been built, so a
  /// jump measured on it lands short.
  double _scrollRange() {
    final geometry = widget.controller.geometry;
    final scroll = widget.controller.scroll;
    if (geometry == null || !scroll.hasClients) return 0;
    return math.max(
        0.0, geometry.contentHeight - scroll.position.viewportDimension);
  }

  void _dragTo(double dy, double trackHeight) {
    final scroll = widget.controller.scroll;
    if (!scroll.hasClients || trackHeight <= 0) return;
    final fraction = (dy / trackHeight).clamp(0.0, 1.0);
    scroll.jumpTo(fraction * _scrollRange());
  }

  @override
  Widget build(BuildContext context) {
    final scroll = widget.controller.scroll;
    final geometry = widget.controller.geometry;
    if (geometry == null ||
        !scroll.hasClients ||
        !scroll.position.hasViewportDimension ||
        geometry.contentHeight <
            scroll.position.viewportDimension * widget.minScreens) {
      return const SizedBox.shrink();
    }

    final tokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final phone = MediaQuery.sizeOf(context).width < galleryPhoneBreakpoint;
    final position = scroll.position;
    final maxExtent = _scrollRange();
    final active = _dragging || _scrolling || (!phone && _hovering);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final fade =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 150);
    // At rest the timeline sits back; it comes forward while it is used. With
    // reduced motion it just stays forward.
    final forward = reduceMotion || active;

    return Semantics(
      label: widget.semanticLabel,
      container: true,
      child: SizedBox(
        width: widget.width,
        child: LayoutBuilder(builder: (context, constraints) {
          final h = constraints.maxHeight;
          final fraction = maxExtent <= 0
              ? 0.0
              : (position.pixels / maxExtent).clamp(0.0, 1.0);
          const thumbHeight = 24.0;
          final thumbTop = fraction * (h - thumbHeight);
          final current = geometry.sectionAt(position.pixels);
          ArDriveGalleryScrubberEntry? entry;
          for (final e in widget.entries) {
            if (e.section <= current) entry = e;
          }
          entry ??= widget.entries.isEmpty ? null : widget.entries.first;
          // The year the view is in: the latest year tick at or above it.
          String? currentYear;
          for (final e in widget.entries) {
            if (e.tick != null && e.section <= current) currentYear = e.tick;
          }

          // Year ticks, thinned so two never touch.
          final ticks = <Widget>[];
          if (!phone) {
            var lastY = -100.0;
            for (final e in widget.entries) {
              final tick = e.tick;
              if (tick == null || e.section >= geometry.sectionOffsets.length) {
                continue;
              }
              final y = geometry.sectionOffsets[e.section] /
                  geometry.contentHeight *
                  h;
              if (y - lastY < 18) continue;
              lastY = y;
              final here = tick == currentYear;
              ticks.add(Positioned(
                top: math.min(y, h - 16),
                right: 12,
                child: Text(
                  tick,
                  key: ValueKey('gallery-scrubber-year-$tick'),
                  style: typography.caption(
                    color: here ? tokens.textHigh : tokens.textMid,
                    fontWeight:
                        here ? ArFontWeight.semiBold : ArFontWeight.book,
                  ),
                ),
              ));
            }
          }

          return MouseRegion(
            onEnter: (_) => setState(() => _hovering = true),
            onExit: (_) => setState(() => _hovering = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: (d) {
                setState(() => _dragging = true);
                _dragTo(d.localPosition.dy, h);
              },
              onVerticalDragUpdate: (d) => _dragTo(d.localPosition.dy, h),
              onVerticalDragEnd: (_) => setState(() => _dragging = false),
              onVerticalDragCancel: () => setState(() => _dragging = false),
              onTapDown: (d) => _dragTo(d.localPosition.dy, h),
              child: AnimatedOpacity(
                key: const ValueKey('gallery-scrubber-fade'),
                opacity: forward ? 1 : ArDriveGalleryScrubber.restOpacity,
                duration: fade,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // The track the years sit along, so it reads as a control.
                    if (!phone)
                      Positioned(
                        top: 0,
                        bottom: 0,
                        right: 1,
                        child: Container(
                          key: const ValueKey('gallery-scrubber-track'),
                          // A little wider while it is in use.
                          width: forward ? 3 : 2,
                          color: tokens.strokeMid,
                        ),
                      ),
                    ...ticks,
                    Positioned(
                      top: thumbTop,
                      right: 0,
                      child: AnimatedOpacity(
                        key: const ValueKey('gallery-scrubber-thumb'),
                        // A phone's handle shows while it is used; on a wide
                        // screen the marker is always on the track.
                        opacity: phone && !active ? 0 : 1,
                        duration: fade,
                        child: Container(
                          width: 4,
                          height: thumbHeight,
                          decoration: BoxDecoration(
                            color: tokens.iconHigh,
                            borderRadius:
                                BorderRadius.circular(ArDriveRadius.sm),
                          ),
                        ),
                      ),
                    ),
                    if (entry != null)
                      Positioned(
                        top: thumbTop + (thumbHeight - 28) / 2,
                        right: ArDriveSpacing.md,
                        child: AnimatedOpacity(
                          key: const ValueKey('gallery-scrubber-bubble'),
                          opacity: _dragging ? 1 : 0,
                          duration: fade,
                          child: IgnorePointer(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: ArDriveSpacing.sm,
                                vertical: ArDriveSpacing.xxs,
                              ),
                              decoration: BoxDecoration(
                                color: tokens.containerL1,
                                border: Border.all(color: tokens.strokeMid),
                                borderRadius:
                                    BorderRadius.circular(ArDriveRadius.sm),
                              ),
                              child: Text(
                                entry.title,
                                maxLines: 1,
                                style: typography.paragraphNormal(
                                  color: tokens.textHigh,
                                  fontWeight: ArFontWeight.semiBold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
