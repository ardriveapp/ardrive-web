import 'dart:async';

import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A tooltip: [message] in a small label under [child], shown while a mouse
/// is over [child] or after a long press on a touch screen.
///
/// Shown, placed and drawn as Material's [Tooltip] is, with one difference:
/// the label never takes a click. It is drawn under what it names, so over
/// whatever comes next, such as the next row of a table. Material's label in
/// Flutter 3.19 is hit like any widget and stays up while the mouse is over
/// it, so a mouse coming down a list went over the last row's label, and the
/// click meant for the row under it landed on the label instead. On a
/// publication, where a click opens a row, the first click did nothing
/// (ardrive-web#2367). Flutter 3.22 makes Material's label ignore the pointer
/// as well (`Tooltip.ignorePointer`).
class ArDriveTooltip extends StatefulWidget {
  const ArDriveTooltip({
    super.key,
    required this.child,
    required this.message,
    this.showOnTap = false,
  });

  final Widget child;
  final String message;

  /// Shows the label on a click or tap as well, for a mark whose only job is
  /// the label, such as [ArDriveInfoTip]. A click anywhere else puts it away.
  final bool showOnTap;

  @override
  State<ArDriveTooltip> createState() => _ArDriveTooltipState();
}

class _ArDriveTooltipState extends State<ArDriveTooltip>
    with SingleTickerProviderStateMixin {
  // Material's timings and placement (material/tooltip.dart, Flutter 3.19).
  static const _verticalOffset = 24.0;
  static const _fadeInDuration = Duration(milliseconds: 150);
  static const _fadeOutDuration = Duration(milliseconds: 75);
  static const _showAfterLongPress = Duration(milliseconds: 1500);
  static const _hoverExitDelay = Duration(milliseconds: 100);

  /// The pointers that can't hover, so show a tooltip on a long press.
  static const _longPressKinds = {
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.stylus,
    PointerDeviceKind.touch,
    PointerDeviceKind.unknown,
    PointerDeviceKind.trackpad,
  };

  /// The tooltips on screen. One at a time: showing one puts the rest away.
  static final Set<_ArDriveTooltipState> _shown = {};

  final _overlay = OverlayPortalController();
  // Made on first show: most tooltips never are, and a ticker made while
  // being disposed reads a widget tree that is going away.
  AnimationController? _backingFade;
  AnimationController get _fade => _backingFade ??= AnimationController(
        duration: _fadeInDuration,
        reverseDuration: _fadeOutDuration,
        vsync: this,
      )..addStatusListener(_onFadeStatus);
  late final _fadeCurve = CurvedAnimation(
    parent: _fade,
    curve: Curves.fastOutSlowIn,
  );
  LongPressGestureRecognizer? _longPress;
  Timer? _timer;

  /// Whether [_onAnyPointer] is told of every pointer, so a click anywhere
  /// puts the label away. Only while the label is up: a long table has a
  /// tooltip on every row, and each would otherwise hear every event.
  bool _hearsEveryPointer = false;

  void _hearEveryPointer(bool hear) {
    if (hear == _hearsEveryPointer) return;
    _hearsEveryPointer = hear;
    final router = GestureBinding.instance.pointerRouter;
    if (hear) {
      router.addGlobalRoute(_onAnyPointer);
    } else {
      router.removeGlobalRoute(_onAnyPointer);
    }
  }

  @override
  void dispose() {
    _hearEveryPointer(false);
    _shown.remove(this);
    _timer?.cancel();
    _longPress
      ?..onLongPressCancel = null
      ..dispose();
    if (_backingFade != null) _fadeCurve.dispose();
    _backingFade?.dispose();
    super.dispose();
  }

  void _onFadeStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) {
      _shown.remove(this);
      _hearEveryPointer(false);
      _overlay.hide();
    }
  }

  void _show() {
    _timer?.cancel();
    _timer = null;
    if (!mounted || !TooltipVisibility.of(context)) return;

    for (final other in _shown.toList()) {
      if (other != this) other._hide();
    }
    _shown.add(this);
    _hearEveryPointer(true);

    if (!_overlay.isShowing) {
      _overlay.show();
      SemanticsService.tooltip(widget.message);
    }
    _fade.forward();
  }

  void _hide({Duration delay = Duration.zero}) {
    _pinned = false;
    _timer?.cancel();
    _timer = null;
    final fade = _backingFade;
    if (fade == null || fade.status == AnimationStatus.dismissed) return;

    if (delay > Duration.zero) {
      _timer = Timer(delay, fade.reverse);
    } else {
      fade.reverse();
    }
  }

  /// When a finger last went down on [child]. A phone's browser follows a
  /// tap with a mouse move over the same spot, which showed the label for a
  /// button the tap had already used: the drawer it opened covered the button,
  /// so nothing ever sent the mouse away, and "Show menu" stayed up over the
  /// drawer's New button.
  DateTime? _lastTouchDown;
  static const _touchHoverGrace = Duration(milliseconds: 1000);

  /// Whether the label was up when the pointer went down: a second tap on
  /// a touch screen puts it away rather than showing it again.
  bool _shownAtDown = false;

  /// Shown by a click, a tap or the keyboard, so it stays when the pointer
  /// leaves, until a click elsewhere.
  bool _pinned = false;

  void _onPointerUp(PointerUpEvent event) {
    if (!widget.showOnTap) return;
    if (event.kind == PointerDeviceKind.touch && _shownAtDown) {
      _hide();
      return;
    }
    _showPinned();
  }

  void _showPinned() {
    _pinned = true;
    _show();
  }

  void _onPointerDown(PointerDownEvent event) {
    final fade = _backingFade?.status;
    _shownAtDown =
        fade == AnimationStatus.forward || fade == AnimationStatus.completed;
    if (event.kind == PointerDeviceKind.touch) _lastTouchDown = DateTime.now();
    if (!_longPressKinds.contains(event.kind)) return;
    // A long press here is the row's - see [ArDriveTooltipLongPressYields].
    if (context
            .getInheritedWidgetOfExactType<ArDriveTooltipLongPressYields>() !=
        null) {
      return;
    }

    (_longPress ??= LongPressGestureRecognizer(
      debugOwner: this,
      supportedDevices: _longPressKinds,
    ))
      ..onLongPress = _onLongPress
      ..onLongPressUp = _onLongPressUp
      // A tap too short to be a long press ends here; a label it pinned
      // stays.
      ..onLongPressCancel = () {
        if (!_pinned) _hide();
      }
      ..addPointer(event);
  }

  void _onLongPressUp() => _hide(delay: _showAfterLongPress);

  void _onLongPress() {
    Feedback.forLongPress(context);
    _show();
  }

  void _onAnyPointer(PointerEvent event) {
    if (event is PointerDownEvent &&
        _longPress?.primaryPointer != event.pointer &&
        !(widget.showOnTap && _isOnChild(event.position))) {
      _hide();
    }
  }

  /// Whether [position] is over [child]: a press there is the mark's own,
  /// handled when it lifts.
  bool _isOnChild(Offset position) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    return (box.localToGlobal(Offset.zero) & box.size).contains(position);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.message.isEmpty) {
      return widget.child;
    }

    // Material's tooltip still names [child] for a screen reader, and is
    // what `find.byTooltip` finds. Only its own label, which takes clicks, is
    // switched off; the one drawn here stands in for it. The switch is put
    // back as it was for [child], so the tooltips inside it still show: a
    // truncated name in a tooltip inside a button that has one.
    final visible = TooltipVisibility.of(context);
    final child = TooltipVisibility(
      visible: false,
      child: Tooltip(
        message: widget.message,
        child: TooltipVisibility(visible: visible, child: widget.child),
      ),
    );
    if (!visible) {
      return child;
    }

    return OverlayPortal(
      controller: _overlay,
      overlayChildBuilder: _buildLabel,
      child: MouseRegion(
        onEnter: (_) {
          final touched = _lastTouchDown;
          if (touched != null &&
              DateTime.now().difference(touched) < _touchHoverGrace) {
            return;
          }
          _show();
        },
        onExit: (_) {
          if (!_pinned) _hide(delay: _hoverExitDelay);
        },
        child: Listener(
          onPointerDown: _onPointerDown,
          onPointerUp: _onPointerUp,
          behavior: HitTestBehavior.opaque,
          child: child,
        ),
      ),
    );
  }

  Widget _buildLabel(BuildContext overlayContext) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final box = context.findRenderObject()! as RenderBox;
    final target = box.localToGlobal(
      box.size.center(Offset.zero),
      ancestor: Overlay.of(context).context.findRenderObject(),
    );
    final isDesktop = switch (Theme.of(context).platform) {
      TargetPlatform.macOS ||
      TargetPlatform.linux ||
      TargetPlatform.windows =>
        true,
      TargetPlatform.android ||
      TargetPlatform.fuchsia ||
      TargetPlatform.iOS =>
        false,
    };

    final label = Positioned.fill(
      bottom: MediaQuery.maybeViewInsetsOf(overlayContext)?.bottom ?? 0.0,
      // Why this widget exists: see [ArDriveTooltip]. Out of the
      // accessibility tree as well, where with the browser's tree on its node
      // would lie over the next row too; [child] already carries the message.
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: CustomSingleChildLayout(
            delegate: _LabelPosition(target: target),
            child: FadeTransition(
              opacity: _fadeCurve,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: isDesktop ? 24 : 32),
                child: DefaultTextStyle(
                  style: Theme.of(context).textTheme.bodyMedium!,
                  child: Container(
                    decoration: BoxDecoration(
                      color: colorTokens.buttonDisabled,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: isDesktop ? 8 : 16,
                      vertical: 4,
                    ),
                    child: Center(
                      widthFactor: 1,
                      heightFactor: 1,
                      child: Text(
                        widget.message,
                        style: typography.paragraphNormal(
                          fontWeight: ArFontWeight.semiBold,
                          color: colorTokens.textMid,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return SelectionContainer.maybeOf(context) == null
        ? label
        : SelectionContainer.disabled(child: label);
  }
}

/// Under the target and centred on it, or over it when there is no room
/// below: Material's tooltip placement.
class _LabelPosition extends SingleChildLayoutDelegate {
  const _LabelPosition({required this.target});

  final Offset target;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) => positionDependentBox(
        size: size,
        childSize: childSize,
        target: target,
        verticalOffset: _ArDriveTooltipState._verticalOffset,
        preferBelow: true,
      );

  @override
  bool shouldRelayout(_LabelPosition oldDelegate) =>
      target != oldDelegate.target;
}

/// Below this, a tooltip shows on hover only and leaves a long press alone,
/// for what is around it to have: a table row that starts selecting on one.
///
/// A tooltip's long press enters the gesture arena before the row's, being
/// deeper, and wins it: a long press on a name or an icon showed its label
/// and never started selecting.
class ArDriveTooltipLongPressYields extends InheritedWidget {
  const ArDriveTooltipLongPressYields({super.key, required super.child});

  @override
  bool updateShouldNotify(ArDriveTooltipLongPressYields oldWidget) => false;
}

/// An info mark: [message] in a tooltip, shown on hover, on a click or tap,
/// and from the keyboard with Enter or Space. A screen reader reads it as a
/// button named by [message]. For a short note beside a control; a longer
/// one belongs in the page or a dialog of its own.
class ArDriveInfoTip extends StatefulWidget {
  const ArDriveInfoTip({
    super.key,
    required this.message,
    this.size = 16,
    this.color,
  });

  final String message;
  final double size;

  /// The mark's colour; textMid when null.
  final Color? color;

  @override
  State<ArDriveInfoTip> createState() => _ArDriveInfoTipState();
}

class _ArDriveInfoTipState extends State<ArDriveInfoTip> {
  final _tooltip = GlobalKey<_ArDriveTooltipState>();

  void _show() => _tooltip.currentState?._showPinned();

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    return Semantics(
      button: true,
      label: widget.message,
      onTap: _show,
      excludeSemantics: true,
      child: ArDriveFocusable(
        onActivate: _show,
        radius: ArDriveRadius.control,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: ArDriveTooltip(
            key: _tooltip,
            message: widget.message,
            showOnTap: true,
            child: Padding(
              padding: const EdgeInsets.all(ArDriveSpacing.xxs),
              child: ArDriveIcons.info(
                size: widget.size,
                color: widget.color ?? colorTokens.textMid,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
