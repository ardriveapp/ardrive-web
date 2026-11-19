import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// Where a [SliverCollapsingHeader] tells [SliverCollapseTail] how tall it
/// is, in the same layout pass, so the tail never reads a stale value.
///
/// It also says, for focus, which of the header and the bar can be reached:
/// the render object sets them after the frame, never during layout.
class CollapsingHeaderExtent {
  double value = 0;

  /// Whether the bar is in enough to be seen and used.
  final barInteractive = ValueNotifier<bool>(false);

  /// Whether any of the header is still on screen.
  final headerOnScreen = ValueNotifier<bool>(true);

  /// Whether the header's anchor row can still be seen: it has faded out
  /// once the bar is 40% in, and then it is neither a target nor a Tab stop.
  final anchorInteractive = ValueNotifier<bool>(true);
}

/// [child], the anchor row of a [SliverCollapsingHeader] (the widget its
/// `anchorKey` is on), made unreachable by pointer, focus and screen reader
/// once it has faded out.
class CollapsingAnchorGate extends StatelessWidget {
  const CollapsingAnchorGate({
    super.key,
    required this.extent,
    required this.child,
  });

  final CollapsingHeaderExtent extent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: extent.anchorInteractive,
      builder: (_, interactive, child) => ExcludeSemantics(
        excluding: !interactive,
        child: ExcludeFocus(
          excluding: !interactive,
          child: IgnorePointer(ignoring: !interactive, child: child),
        ),
      ),
      child: child,
    );
  }
}

/// A header that is part of its scroll view's content, with a slim bar pinned
/// at the top once [anchorKey]'s widget would leave.
///
/// [header] is laid out at its natural height and scrolls away one to one
/// with the content under it: there is no state, no animation and no second
/// layout, only the scroll offset. [bar] is [barHeight] tall and is drawn over
/// the top of the viewport, sliding down over the header as the offset goes from
/// where [anchorKey]'s top is [barHeight] below the viewport's top to where it
/// reaches it. Past the header the bar stays, and a pinned sliver after it
/// (such as a table's column header) sits under it, as it does under any
/// pinned header.
///
/// It must be the first sliver of a vertical scroll view that reads down.
class SliverCollapsingHeader extends MultiChildRenderObjectWidget {
  SliverCollapsingHeader({
    super.key,
    required Widget header,
    required Widget bar,
    required this.barHeight,
    this.anchorKey,
    this.extent,
  }) : super(
          children: [
            if (extent == null)
              header
            else
              // Off screen it is no Tab stop: focus would scroll it back.
              ValueListenableBuilder<bool>(
                valueListenable: extent.headerOnScreen,
                builder: (_, onScreen, child) =>
                    ExcludeFocus(excluding: !onScreen, child: child!),
                child: header,
              ),
            if (extent == null)
              bar
            else
              // Not yet in, it is neither seen nor reachable.
              ValueListenableBuilder<bool>(
                valueListenable: extent.barInteractive,
                builder: (_, interactive, child) => ExcludeFocus(
                  excluding: !interactive,
                  child: IgnorePointer(ignoring: !interactive, child: child),
                ),
                child: bar,
              ),
          ],
        );

  final double barHeight;

  /// A widget inside [header] whose top is where the bar takes over. Absent,
  /// the bar starts when the header starts to move.
  final GlobalKey? anchorKey;

  /// Told the header's height, for [SliverCollapseTail].
  final CollapsingHeaderExtent? extent;

  @override
  RenderSliverCollapsingHeader createRenderObject(BuildContext context) =>
      RenderSliverCollapsingHeader(
        barHeight: barHeight,
        anchorKey: anchorKey,
        extent: extent,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSliverCollapsingHeader renderObject,
  ) {
    renderObject
      ..barHeight = barHeight
      ..anchorKey = anchorKey
      ..extent = extent;
  }
}

class _ParentData extends ContainerBoxParentData<RenderBox> {}

class RenderSliverCollapsingHeader extends RenderSliver
    with
        ContainerRenderObjectMixin<RenderBox, _ParentData>,
        RenderSliverHelpers {
  RenderSliverCollapsingHeader({
    required double barHeight,
    GlobalKey? anchorKey,
    CollapsingHeaderExtent? extent,
  })  : _barHeight = barHeight,
        _anchorKey = anchorKey,
        _extent = extent;

  double _barHeight;
  double get barHeight => _barHeight;
  set barHeight(double value) {
    if (value == _barHeight) return;
    _barHeight = value;
    markNeedsLayout();
  }

  GlobalKey? _anchorKey;
  set anchorKey(GlobalKey? value) {
    if (value == _anchorKey) return;
    _anchorKey = value;
    markNeedsLayout();
  }

  CollapsingHeaderExtent? _extent;
  set extent(CollapsingHeaderExtent? value) {
    if (value == _extent) return;
    _extent = value;
    markNeedsLayout();
  }

  /// How far the bar has come in, 0 to 1, as of the last layout.
  double _progress = 0;
  double get progress => _progress;

  double _scrolled = 0;

  /// How far the bar itself is in, 0 to 1. It starts only once the header's
  /// anchor row has finished fading out ([_anchorGoneBy]), so the title and
  /// buttons of the two are never drawn together.
  double _barProgress = 0;
  double get barProgress => _barProgress;

  /// How much of the bar's coming in the header's anchor row is gone by:
  /// it fades out in the first of it, so the title and the actions are never
  /// on screen twice.
  static const double _anchorGoneBy = 0.4;

  RenderBox get _header => firstChild!;
  RenderBox get _bar => lastChild!;

  /// Below this the bar is neither seen by a pointer nor by a screen reader.
  static const double _interactiveFrom = 0.5;

  /// How far above its place the bar starts, and slides down from: all of it,
  /// so it is wholly off the top at rest.
  double get _barSlide => _barHeight;

  Offset _barOffset() => Offset(0, -(1 - _barProgress) * _barSlide);

  /// The anchor row's fade pushes a layer inside a clip: the clip has to be
  /// a layer too, or it is lost on the way.
  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! _ParentData) child.parentData = _ParentData();
  }

  @override
  void performLayout() {
    assert(constraints.axis == Axis.vertical &&
        constraints.growthDirection == GrowthDirection.forward &&
        constraints.axisDirection == AxisDirection.down);
    final width = constraints.crossAxisExtent;
    _header.layout(
      BoxConstraints(minWidth: width, maxWidth: width),
      parentUsesSize: true,
    );
    _bar.layout(BoxConstraints.tightFor(width: width, height: _barHeight));

    final height = _header.size.height;
    _extent?.value = height;
    final offset = math.max(0.0, constraints.scrollOffset);
    _scrolled = offset;

    // Where the bar starts to come in: when the anchor's top is a bar's
    // height below the top. It is done by the time the anchor's top is at
    // the top, or by the time the header's rest would slip under the bar.
    var anchorTop = 0.0;
    final anchor = _anchorKey?.currentContext?.findRenderObject();
    if (anchor is RenderBox && anchor.attached && anchor.hasSize) {
      final at = anchor.localToGlobal(Offset.zero, ancestor: _header);
      anchorTop = at.dy;
    }
    final start = math.max(0.0, anchorTop - _barHeight);
    final end = math.min(
      start + _barHeight,
      math.max(height - _barHeight, start + 1),
    );
    final progress = ((offset - start) / (end - start)).clamp(0.0, 1.0);
    final wasInteractive = _barProgress >= _interactiveFrom;
    _progress = progress;
    _barProgress =
        ((progress - _anchorGoneBy) / (1 - _anchorGoneBy)).clamp(0.0, 1.0);
    if (wasInteractive != (_barProgress >= _interactiveFrom)) {
      markNeedsSemanticsUpdate();
    }
    _publish(
      interactive: _barProgress >= _interactiveFrom,
      headerOnScreen: offset < height,
      anchorInteractive: _progress < _anchorGoneBy,
    );

    final remaining = constraints.remainingPaintExtent;
    final headerLeft = math.max(0.0, height - offset);
    geometry = SliverGeometry(
      scrollExtent: height,
      paintExtent: math.min(math.max(headerLeft, _barHeight), remaining),
      layoutExtent: math.min(headerLeft, remaining),
      maxPaintExtent: height,
      cacheExtent: calculateCacheOffset(constraints, from: 0, to: height),
      hasVisualOverflow: true,
      // The bar is pinned over the top: scrolling something into view stops
      // below it, as it does below a pinned app bar.
      maxScrollObstructionExtent: _barHeight,
    );
  }

  bool _publishScheduled = false;
  bool _interactive = false;
  bool _headerOnScreen = true;
  bool _anchorInteractive = true;

  /// Tells [CollapsingHeaderExtent]'s notifiers, after this frame: a widget
  /// cannot be rebuilt from layout.
  void _publish({
    required bool interactive,
    required bool headerOnScreen,
    required bool anchorInteractive,
  }) {
    _interactive = interactive;
    _headerOnScreen = headerOnScreen;
    _anchorInteractive = anchorInteractive;
    final extent = _extent;
    if (extent == null || _publishScheduled) return;
    if (extent.barInteractive.value == interactive &&
        extent.headerOnScreen.value == headerOnScreen &&
        extent.anchorInteractive.value == anchorInteractive) {
      return;
    }
    _publishScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _publishScheduled = false;
      // The latest, not what was seen when scheduled.
      final extent = _extent;
      if (extent == null) return;
      extent.barInteractive.value = _interactive;
      extent.headerOnScreen.value = _headerOnScreen;
      extent.anchorInteractive.value = _anchorInteractive;
    });
  }

  @override
  double childMainAxisPosition(RenderBox child) =>
      identical(child, _header) ? -_scrolled : _barOffset().dy;

  @override
  double childCrossAxisPosition(RenderBox child) => 0;

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translate(0.0, childMainAxisPosition(child));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_scrolled < _header.size.height) {
      _paintHeader(context, offset);
    }
    // Opaque all the way: a bar fading over the header's lines would show
    // them through it. It slides down over them instead.
    if (_barProgress <= 0) return;
    context.paintChild(_bar, offset + _barOffset());
  }

  bool _warnedOfBoundaries = false;

  /// Debug only, once: says if the header holds a [RepaintBoundary], which the
  /// banded painting of the anchor row cannot share between its bands.
  bool _debugWarnOfRepaintBoundaries() {
    if (_warnedOfBoundaries) return true;
    _warnedOfBoundaries = true;
    var found = false;
    void visit(RenderObject object) {
      if (!identical(object, _header) && object.isRepaintBoundary) found = true;
      object.visitChildren(visit);
    }

    visit(_header);
    if (found) {
      debugPrint(
        'SliverCollapsingHeader: the header contains a RepaintBoundary; its '
        'anchor row is painted in bands, which a boundary layer does not '
        'survive. Keep boundaries out of the header.',
      );
    }
    return true;
  }

  /// The header at its place. While the bar is coming in, its anchor row (the
  /// title and the actions) fades out by [_anchorGoneBy], on its own: the
  /// rest of the header goes on scrolling under the bar, but the bar's own
  /// title and buttons are never drawn over a second pair.
  void _paintHeader(PaintingContext context, Offset offset) {
    assert(_debugWarnOfRepaintBoundaries());
    final at = Offset(0, -_scrolled);
    final box = _anchorKey?.currentContext?.findRenderObject();
    if (_progress <= 0 || box is! RenderBox || !box.attached || !box.hasSize) {
      context.paintChild(_header, offset + at);
      return;
    }
    final alpha = (1 - _progress / _anchorGoneBy).clamp(0.0, 1.0);
    final row = (box.localToGlobal(Offset.zero, ancestor: _header) & box.size)
        .shift(at);
    // Everything but the row, as bands around it: a clip with a hole in it
    // did not hold on the web, so each band is a plain rectangle.
    //
    // The header is painted once per band, so it must hold no RepaintBoundary:
    // a boundary child paints into a layer of its own, and a layer painted
    // under several clips is not what a plain widget drawn several times is
    // (it is the same layer attached twice). None exists in the header today;
    // [_debugWarnOfRepaintBoundaries] says so in debug builds if one appears.
    final whole = (Offset.zero & _header.size).shift(at).inflate(8);
    final bands = [
      Rect.fromLTRB(whole.left, whole.top, whole.right, row.top),
      Rect.fromLTRB(whole.left, row.bottom, whole.right, whole.bottom),
      Rect.fromLTRB(whole.left, row.top, row.left, row.bottom),
      Rect.fromLTRB(row.right, row.top, whole.right, row.bottom),
    ];
    for (final band in bands) {
      if (band.isEmpty) continue;
      context.pushClipRect(
        true,
        offset,
        band,
        (context, offset) => context.paintChild(_header, offset + at),
      );
    }
    if (alpha <= 0) return;
    context.pushClipRect(true, offset, row, (context, offset) {
      context.pushOpacity(
        offset,
        (alpha * 255).round(),
        (context, offset) => context.paintChild(_header, offset + at),
      );
    });
  }

  @override
  bool hitTestChildren(
    SliverHitTestResult result, {
    required double mainAxisPosition,
    required double crossAxisPosition,
  }) {
    if (_barProgress >= _interactiveFrom) {
      final barTop = _barOffset().dy;
      if (mainAxisPosition >= barTop &&
          mainAxisPosition < barTop + _barHeight) {
        if (hitTestBoxChild(
          BoxHitTestResult.wrap(result),
          _bar,
          mainAxisPosition: mainAxisPosition,
          crossAxisPosition: crossAxisPosition,
        )) {
          return true;
        }
      }
    }
    // The header is under the bar while the bar is shown.
    if (_barProgress < 1 || mainAxisPosition >= _barHeight) {
      return hitTestBoxChild(
        BoxHitTestResult.wrap(result),
        _header,
        mainAxisPosition: mainAxisPosition,
        crossAxisPosition: crossAxisPosition,
      );
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (_scrolled < _header.size.height) visitor(_header);
    if (_barProgress >= _interactiveFrom) visitor(_bar);
  }
}

/// The last sliver of a scroll view that has a [SliverCollapsingHeader]: room
/// after the content, so that a short list can still be scrolled until what
/// follows the header sits just under the [pinnedInset] the bar covers.
///
/// Without it a list shorter than the window has no scroll range, and the
/// header could not collapse. The range it adds depends only on the window and
/// the content, never on the offset, so it cannot move under the reader.
class SliverCollapseTail extends StatelessWidget {
  const SliverCollapseTail({
    super.key,
    required this.extent,
    required this.pinnedInset,
    this.minHeight = 0,
  });

  final CollapsingHeaderExtent extent;

  /// What the pinned bar covers at the top of the window.
  final double pinnedInset;

  /// Room to leave under the content however tall it is.
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(builder: (context, constraints) {
      // Everything between the header and here.
      final content = constraints.precedingScrollExtent - extent.value;
      final height = math.max(
        minHeight,
        constraints.viewportMainAxisExtent - pinnedInset - content,
      );
      return SliverToBoxAdapter(child: SizedBox(height: height));
    });
  }
}
