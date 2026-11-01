import 'dart:async';

import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

enum ToggleState { on, off, disabled }

class ArDriveToggleSwitch extends StatefulWidget {
  const ArDriveToggleSwitch({
    super.key,
    required this.text,
    this.textStyle,
    this.onChanged,
    this.value = false,
    this.isEnabled = true,
    this.alignRight = false,
  });

  final String text;
  final TextStyle? textStyle;
  final bool value;
  final bool isEnabled;
  final FutureOr Function(bool value)? onChanged;
  final bool alignRight;

  @override
  State<ArDriveToggleSwitch> createState() => ArDriveToggleSwitchState();
}

@visibleForTesting
class ArDriveToggleSwitchState extends State<ArDriveToggleSwitch> {
  @visibleForTesting
  late ToggleState state;

  final animationDuration = const Duration(milliseconds: 400);

  bool _isAnimating = false;

  /// Whether the keyboard has focus here, so the track shows a ring.
  bool _showFocus = false;

  late bool _checked;

  @override
  void initState() {
    _changeState();

    super.initState();
  }

  @override
  void didUpdateWidget(ArDriveToggleSwitch oldWidget) {
    _changeState();

    super.didUpdateWidget(oldWidget);
  }

  void _changeState() {
    if (widget.isEnabled) {
      if (widget.value) {
        state = ToggleState.on;
        _checked = true;
      } else {
        state = ToggleState.off;
        _checked = false;
      }
    } else {
      state = ToggleState.disabled;
      _checked = widget.value;
    }

    setState(() {});
  }

  Alignment alignment() {
    switch (state) {
      case ToggleState.on:
        return Alignment.centerRight;
      case ToggleState.off:
        return Alignment.centerLeft;

      case ToggleState.disabled:
        return _checked ? Alignment.centerRight : Alignment.centerLeft;
    }
  }

  Color colorBackground() {
    final theme = ArDriveTheme.of(context).themeData.toggleTheme;
    switch (state) {
      case ToggleState.on:
        return theme.backgroundOnColor;
      case ToggleState.off:
        return theme.backgroundOffColor;

      case ToggleState.disabled:
        return theme.backgroundOffDisabled;
    }
  }

  Color colorIndicator() {
    final theme = ArDriveTheme.of(context).themeData.toggleTheme;

    switch (state) {
      case ToggleState.on:
        return theme.indicatorColorOn;
      case ToggleState.off:
        return theme.indicatorColorOff;
      case ToggleState.disabled:
        return theme.indicatorColorDisabled;
    }
  }

  Future<void> _toggleValue() async {
    if (_isAnimating) {
      return;
    }

    if (state != ToggleState.disabled) {
      if (state == ToggleState.on) {
        state = ToggleState.off;
      } else {
        state = ToggleState.on;
      }
      _checked = !_checked;

      _isAnimating = true;

      await widget.onChanged?.call(_checked);

      _isAnimating = false;
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final textWidget = Text(
      widget.text,
      style: widget.textStyle ??
          ArDriveTypographyNew.of(context).paragraphNormal(
            color: colorTokens.textHigh,
            fontWeight: ArFontWeight.semiBold,
          ),
    );
    final isEnabled = state != ToggleState.disabled;

    // One switch for a screen reader and the keyboard: its label, whether it
    // is on, and Space or Enter to flip it. It was a row of text and shapes
    // under a bare tap handler, so a screen reader heard only the label and
    // the keyboard could not reach it.
    return Semantics(
      container: true,
      toggled: _checked,
      enabled: isEnabled,
      label: widget.text,
      onTap: isEnabled ? _toggleValue : null,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: isEnabled,
        onShowFocusHighlight: (show) => setState(() => _showFocus = show),
        mouseCursor:
            isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => _toggleValue(),
          ),
        },
        child: GestureDetector(
          onTap: _toggleValue,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              widget.alignRight
                  // Takes the row, so the switch sits at its end, and wraps
                  // in a narrow space rather than running off it.
                  ? Expanded(child: textWidget)
                  : Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: _toggle(),
                    ),
              const SizedBox(
                width: 8,
              ),
              widget.alignRight ? _toggle() : textWidget
            ],
          ),
        ),
      ),
    );
  }

  Widget _toggle() {
    return AnimatedContainer(
      width: 36,
      height: 20,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: colorBackground(),
        border: _showFocus
            ? Border.all(
                color: ArDriveTheme.of(context).themeData.colorTokens.textHigh,
                width: 2,
                strokeAlign: BorderSide.strokeAlignOutside,
              )
            : null,
      ),
      duration: animationDuration,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: AnimatedAlign(
          onEnd: () {
            _isAnimating = false;
          },
          alignment: alignment(),
          duration: animationDuration,
          child: _ToggleCircle(
            color: colorIndicator(),
            checked: _checked,
          ),
        ),
      ),
    );
  }
}

class _ToggleCircle extends StatefulWidget {
  const _ToggleCircle({
    required this.color,
    required this.checked,
  });

  final Color color;
  final bool checked;

  @override
  State<_ToggleCircle> createState() => _ToggleCircleState();
}

class _ToggleCircleState extends State<_ToggleCircle> {
  final animationDuration = const Duration(milliseconds: 300);
  bool isAnimating = false;
  late bool checked;

  @override
  void initState() {
    checked = widget.checked;
    super.initState();
  }

  @override
  void didUpdateWidget(covariant _ToggleCircle oldWidget) {
    if (checked != widget.checked) {
      setState(() {
        isAnimating = true;
      });

      Future.delayed(animationDuration).then((value) => setState(() {
            isAnimating = false;
          }));
      checked = widget.checked;
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: animationDuration,
      width: isAnimating ? 18 : 12,
      height: 12,
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: isAnimating
            ? widget.checked
                ? const BorderRadius.only(
                    topLeft: Radius.circular(80),
                    bottomLeft: Radius.circular(80),
                    topRight: Radius.circular(90),
                    bottomRight: Radius.circular(90),
                  )
                : const BorderRadius.only(
                    topLeft: Radius.circular(90),
                    bottomLeft: Radius.circular(90),
                    topRight: Radius.circular(80),
                    bottomRight: Radius.circular(80),
                  )
            : BorderRadius.circular(90),
      ),
    );
  }
}
