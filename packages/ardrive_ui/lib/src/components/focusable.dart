import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Makes [child] reachable with Tab and pressable with Enter or Space, and
/// draws the keyboard focus ring around it (README: every control is
/// reachable by keyboard and shows a focus ring).
///
/// Only the keyboard shows the ring; a click doesn't, as on the web. Nothing
/// changes for a mouse. Without [onActivate] it is not focusable at all.
class ArDriveFocusable extends StatefulWidget {
  const ArDriveFocusable({
    super.key,
    required this.child,
    required this.onActivate,
    this.radius = ArDriveRadius.sm,
    this.inflate = 2,
    this.focusNode,
  });

  final Widget child;
  final VoidCallback? onActivate;

  /// The ring's corner radius.
  final double radius;

  /// How far outside the child the ring is drawn, so it takes no room.
  final double inflate;

  final FocusNode? focusNode;

  @override
  State<ArDriveFocusable> createState() => _ArDriveFocusableState();
}

const _activateKeys = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
};

class _ArDriveFocusableState extends State<ArDriveFocusable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final onActivate = widget.onActivate;
    return FocusableActionDetector(
      enabled: onActivate != null,
      focusNode: widget.focusNode,
      mouseCursor: MouseCursor.defer,
      // Its own Enter and Space, nearest the focus: the app maps them at its
      // root, and a table around the control (Enter opens its row) took the
      // key first, so a row's menu button did nothing.
      shortcuts: _activateKeys,
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            onActivate?.call();
            return null;
          },
        ),
      },
      child: CustomPaint(
        foregroundPainter: _focused
            ? ArDriveFocusRingPainter(
                ArDriveTheme.of(context).themeData.colorTokens.focusRing,
                radius: widget.radius,
                inflate: widget.inflate,
              )
            : null,
        child: widget.child,
      ),
    );
  }
}

/// The keyboard focus ring: 2 px, just outside what it surrounds.
class ArDriveFocusRingPainter extends CustomPainter {
  ArDriveFocusRingPainter(
    this.color, {
    this.radius = ArDriveRadius.sm,
    this.inflate = 3,
  });

  final Color color;
  final double radius;
  final double inflate;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (Offset.zero & size).inflate(inflate),
        Radius.circular(radius),
      ),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(ArDriveFocusRingPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.inflate != inflate;
}
