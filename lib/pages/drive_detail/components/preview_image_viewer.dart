import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// How far a photo is zoomed in at most.
const double previewMaxScale = 5;

/// What a double tap zooms to.
const double previewDoubleTapScale = 2.5;

/// A full-screen photo you can move through and look into.
///
/// - Swipe left or right for the next or previous one, when there is one;
///   the photo follows the finger and springs back when the swipe is short.
/// - Swipe down to close.
/// - Pinch, or double tap (double click), to zoom; drag to look around while
///   zoomed. Swiping to the next photo waits until it is zoomed out again.
///
/// One gesture recogniser does all of it, so a pinch is never mistaken for a
/// swipe or the other way round.
class PreviewImageViewer extends StatefulWidget {
  const PreviewImageViewer({
    super.key,
    required this.child,
    this.onNext,
    this.onPrevious,
    this.onClose,
  });

  final Widget child;

  /// Null where there is no next photo: the swipe springs back.
  final VoidCallback? onNext;
  final VoidCallback? onPrevious;
  final VoidCallback? onClose;

  @override
  State<PreviewImageViewer> createState() => PreviewImageViewerState();
}

class PreviewImageViewerState extends State<PreviewImageViewer>
    with SingleTickerProviderStateMixin {
  double _scale = 1;
  Offset _offset = Offset.zero;

  // Gesture in progress.
  double _startScale = 1;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;
  Offset _swipe = Offset.zero;
  bool _swiping = false;
  Offset? _doubleTapAt;

  late final AnimationController _settle;
  double _fromScale = 1, _toScale = 1;
  Offset _fromOffset = Offset.zero, _toOffset = Offset.zero;
  Offset _fromSwipe = Offset.zero;

  /// Zoomed in: drags look around instead of swiping.
  bool get isZoomed => _scale > 1.01;

  Size get _size => (context.size ?? Size.zero);

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(vsync: this)..addListener(_onSettle);
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  Duration get _settleDuration => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 200);

  /// Keeps the zoomed photo covering the screen: no gap opens at an edge.
  Offset _clamp(Offset offset, double scale) {
    final size = _size;
    final minX = size.width * (1 - scale);
    final minY = size.height * (1 - scale);
    return Offset(
      offset.dx.clamp(math.min(minX, 0), 0),
      offset.dy.clamp(math.min(minY, 0), 0),
    );
  }

  void _animateTo({required double scale, required Offset offset}) {
    _fromScale = _scale;
    _toScale = scale;
    _fromOffset = _offset;
    _toOffset = offset;
    _fromSwipe = _swipe;
    _settle
      ..duration = _settleDuration
      ..forward(from: 0);
    if (_settle.duration == Duration.zero) _onSettle();
  }

  void _onSettle() {
    final t = Curves.easeOut.transform(_settle.value);
    setState(() {
      _scale = _fromScale + (_toScale - _fromScale) * t;
      _offset = Offset.lerp(_fromOffset, _toOffset, t)!;
      _swipe = Offset.lerp(_fromSwipe, Offset.zero, t)!;
    });
  }

  /// Zooms to [scale] keeping the point under [focal] where it is.
  Offset _offsetZoomingAt(Offset focal, double from, double to) =>
      focal - (focal - _offset) * (to / from);

  void _onScaleStart(ScaleStartDetails details) {
    _settle.stop();
    _startScale = _scale;
    _startOffset = _offset;
    _startFocal = details.localFocalPoint;
    _swiping = details.pointerCount < 2 && !isZoomed;
    _swipe = Offset.zero;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_swiping && details.pointerCount >= 2) {
      // A second finger came down: it is a pinch after all.
      _swiping = false;
      _swipe = Offset.zero;
    }
    setState(() {
      if (_swiping) {
        _swipe = details.localFocalPoint - _startFocal;
        return;
      }
      final scale =
          (_startScale * details.scale).clamp(1.0, previewMaxScale).toDouble();
      final focal = details.localFocalPoint;
      // Zoom about where the fingers started, then follow them.
      final zoomed = _startFocal -
          (_startFocal - _startOffset) * (scale / _startScale) +
          (focal - _startFocal);
      _scale = scale;
      _offset = _clamp(zoomed, scale);
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (!_swiping) {
      if (_scale <= 1.01) {
        _animateTo(scale: 1, offset: Offset.zero);
      }
      return;
    }
    _swiping = false;
    final size = _size;
    final velocity = details.velocity.pixelsPerSecond;
    final dx = _swipe.dx, dy = _swipe.dy;
    final horizontal = dx.abs() > dy.abs();
    if (horizontal) {
      final far = dx.abs() > size.width * 0.2 || velocity.dx.abs() > 600;
      if (far && dx < 0 && widget.onNext != null) {
        _swipe = Offset.zero;
        widget.onNext!();
        return;
      }
      if (far && dx > 0 && widget.onPrevious != null) {
        _swipe = Offset.zero;
        widget.onPrevious!();
        return;
      }
    } else if (dy > 0 && (dy > 120 || velocity.dy > 700)) {
      _swipe = Offset.zero;
      widget.onClose?.call();
      return;
    }
    _animateTo(scale: 1, offset: Offset.zero);
  }

  void _onDoubleTap() {
    final at = _doubleTapAt ?? _size.center(Offset.zero);
    if (isZoomed) {
      _animateTo(scale: 1, offset: Offset.zero);
    } else {
      _animateTo(
        scale: previewDoubleTapScale,
        offset: _clamp(
          _offsetZoomingAt(at, _scale, previewDoubleTapScale),
          previewDoubleTapScale,
        ),
      );
    }
  }

  /// Ctrl or Cmd and the mouse wheel zoom, as in a browser.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final keys = HardwareKeyboard.instance;
    if (!keys.isControlPressed && !keys.isMetaPressed) return;
    final to = (_scale * (event.scrollDelta.dy < 0 ? 1.25 : 0.8))
        .clamp(1.0, previewMaxScale)
        .toDouble();
    setState(() {
      _offset = to <= 1.01
          ? Offset.zero
          : _clamp(_offsetZoomingAt(event.localPosition, _scale, to), to);
      _scale = to;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // A swipe down fades the photo as it goes, as a hint it will close.
    final down = math.max(0.0, _swipe.dy);
    final horizontal = _swipe.dx.abs() >= _swipe.dy.abs();
    final fade =
        horizontal ? 1.0 : (1 - down / (size.height * 0.8)).clamp(0.4, 1.0);
    final follow = horizontal ? Offset(_swipe.dx, 0) : Offset(0, down);

    return Listener(
      onPointerSignal: _onPointerSignal,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
        onDoubleTap: _onDoubleTap,
        child: ClipRect(
          child: Opacity(
            opacity: fade.toDouble(),
            child: Transform(
              transform: Matrix4.identity()
                ..translate(_offset.dx + follow.dx, _offset.dy + follow.dy)
                ..scale(_scale),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
