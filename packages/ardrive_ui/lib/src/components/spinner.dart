import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

enum ArDriveSpinnerSize {
  /// 16: inside a button, a row or next to a line of text.
  small(16, 2),

  /// 32: on its own, while a dialog, panel or page loads.
  large(32, 3);

  const ArDriveSpinnerSize(this.dimension, this.strokeWidth);

  final double dimension;
  final double strokeWidth;
}

/// Something is loading. Two sizes, one look.
///
/// Material's own indeterminate ring starts as a dot and grows for the first
/// second, which reads as a speck or a glitch. This one is a full arc from
/// the first frame, turning.
class ArDriveSpinner extends StatefulWidget {
  const ArDriveSpinner({
    super.key,
    this.size = ArDriveSpinnerSize.small,
    this.color,
    this.value,
    this.semanticsLabel,
  });

  final ArDriveSpinnerSize size;

  /// Defaults to iconMid. Pass textOnPrimary on a primary button.
  final Color? color;

  /// Null spins; a value from 0 to 1 shows that much done.
  final double? value;

  final String? semanticsLabel;

  @override
  State<ArDriveSpinner> createState() => _ArDriveSpinnerState();
}

class _ArDriveSpinnerState extends State<ArDriveSpinner>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(ArDriveSpinner oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.value == null) {
      _controller ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1000),
      )..repeat();
    } else {
      _controller?.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final size = widget.size;
    final color = widget.color ?? colorTokens.iconMid;
    final controller = _controller;
    // Spinning: a fixed three-quarter arc, turned. Drawn by the same
    // indicator as a measured one, so it looks the same and a finder for it
    // still finds it.
    final ring = CircularProgressIndicator(
      value: controller == null ? widget.value : _spinningArc,
      strokeWidth: size.strokeWidth,
      strokeCap: StrokeCap.round,
      color: color,
      backgroundColor: controller == null ? colorTokens.strokeLow : null,
      semanticsLabel: widget.semanticsLabel,
    );
    return SizedBox.square(
      dimension: size.dimension,
      child: controller == null
          ? ring
          // The arc is for the eye: a screen reader would read it out as 75%.
          : Semantics(
              label: widget.semanticsLabel,
              child: ExcludeSemantics(
                child: RepaintBoundary(
                  child: RotationTransition(turns: controller, child: ring),
                ),
              ),
            ),
    );
  }
}

/// How much of the ring a spinning one draws.
const double _spinningArc = 0.75;

/// A progress bar: how far something has got, or that it is under way when
/// [value] is null.
///
/// A new value is walked to from wherever the fill is, never from zero, so
/// progress reported in steps still reads as one movement.
class ArDriveLinearProgress extends StatefulWidget {
  const ArDriveLinearProgress({
    super.key,
    this.value,
    this.semanticsLabel,
    this.duration = const Duration(milliseconds: 300),
    this.color,
  });

  /// From 0 to 1, or null when how far along isn't known.
  final double? value;

  /// The fill. Leave null for the primary colour; pass another to say the
  /// progress has stopped or finished without moving the bar, such as a
  /// download waiting to reconnect.
  final Color? color;

  final String? semanticsLabel;

  /// How long the fill takes to reach a new value. Zero jumps.
  final Duration duration;

  @override
  State<ArDriveLinearProgress> createState() => _ArDriveLinearProgressState();
}

class _ArDriveLinearProgressState extends State<ArDriveLinearProgress> {
  /// Where the fill last stood. While the value is unknown the tween holds
  /// here, so it resumes from it: aimed at zero, the fill drifted down out of
  /// sight and climbed back when a value returned.
  double _lastValue = 0;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final value = widget.value;
    if (value != null) _lastValue = value.clamp(0.0, 1.0);

    Widget bar(double? value) => LinearProgressIndicator(
          value: value,
          minHeight: 4,
          color: widget.color ?? colorTokens.buttonPrimaryDefault,
          backgroundColor: colorTokens.strokeMid,
          semanticsLabel: widget.semanticsLabel,
        );

    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: _lastValue),
        duration: widget.duration,
        builder: (context, animated, _) => bar(value == null ? null : animated),
      ),
    );
  }
}
