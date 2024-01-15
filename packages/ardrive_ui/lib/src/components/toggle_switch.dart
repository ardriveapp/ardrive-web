import 'dart:async';

import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

enum ToggleState { on, off, disabled }

class ArDriveToggleSwitch extends StatefulWidget {
  const ArDriveToggleSwitch({
    super.key,
    required this.text,
    this.onChanged,
    this.value = false,
    this.isEnabled = true,
  });

  final String text;
  final bool value;
  final bool isEnabled;
  final FutureOr Function(bool value)? onChanged;

  @override
  State<ArDriveToggleSwitch> createState() => ArDriveToggleSwitchState();
}

@visibleForTesting
class ArDriveToggleSwitchState extends State<ArDriveToggleSwitch> {
  @visibleForTesting
  late ToggleState state;

  final animationDuration = const Duration(milliseconds: 400);

  bool _isAnimating = false;

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

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () async {
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
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: _toggle(),
            ),
            const SizedBox(
              width: 8,
            ),
            Text(
              widget.text,
              style: ArDriveTypography.body.bodyRegular(),
            ),
          ],
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
    Key? key,
    required this.color,
    required this.checked,
  }) : super(key: key);

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
