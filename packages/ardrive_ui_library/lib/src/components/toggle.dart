import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';

enum ToggleState { on, off, disabled }

class ArDriveToggle extends StatefulWidget {
  const ArDriveToggle({
    super.key,
    this.initialState = ToggleState.off,
  });

  final ToggleState initialState;

  @override
  State<ArDriveToggle> createState() => _ArDriveToggleState();
}

class _ArDriveToggleState extends State<ArDriveToggle> {
  late ToggleState _state;

  final animationDuration = const Duration(milliseconds: 400);

  @override
  void initState() {
    _state = widget.initialState;

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (_state != ToggleState.disabled) {
          if (_state == ToggleState.on) {
            _state = ToggleState.off;
          } else {
            _state = ToggleState.on;
          }
          setState(() {});
        }
      },
      child: AnimatedContainer(
        width: 36,
        height: 20,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: colorBackground(),
        ),
        // TODO(@thiagocarvalhodev): use correct color here
        duration: animationDuration,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: AnimatedAlign(
            alignment: alingment(),
            duration: animationDuration,
            child: _ToggleCircle(
              color: colorIndicator(),
              state: _state,
            ),
          ),
        ),
      ),
    );
  }

  Alignment alingment() {
    switch (_state) {
      case ToggleState.on:
        return Alignment.centerRight;
      case ToggleState.off:
        return Alignment.centerLeft;

      case ToggleState.disabled:
        return Alignment.centerLeft;
    }
  }

  Color colorBackground() {
    final theme = ArDriveTheme.of(context).themeData.toggleTheme;
    switch (_state) {
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

    switch (_state) {
      case ToggleState.on:
        return theme.indicatorColorOn;
      case ToggleState.off:
        return theme.indicatorColorOff;
      case ToggleState.disabled:
        return theme.indicatorColorDisabled;
    }
  }
}

class _ToggleCircle extends StatefulWidget {
  const _ToggleCircle({
    Key? key,
    required this.color,
    required this.state,
  }) : super(key: key);

  final Color color;
  final ToggleState state;

  @override
  State<_ToggleCircle> createState() => _ToggleCircleState();
}

class _ToggleCircleState extends State<_ToggleCircle> {
  final animationDuration = const Duration(milliseconds: 300);
  bool isAnimating = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(covariant _ToggleCircle oldWidget) {
    setState(() {
      isAnimating = true;
    });

    Future.delayed(animationDuration).then((value) => setState(() {
          isAnimating = false;
        }));

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
              ? widget.state == ToggleState.on
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
        ));
  }
}
