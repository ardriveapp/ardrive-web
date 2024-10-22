import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// TODO: move this to ardrive_ui
class HoverWidget extends StatefulWidget {
  final Widget child;
  final double hoverScale;
  final Color? hoverColor;
  final String? tooltip;
  final EdgeInsets? padding;

  const HoverWidget({
    super.key,
    required this.child,
    this.hoverScale = 1.0,
    this.hoverColor,
    this.tooltip,
    this.padding,
  });

  @override
  // ignore: library_private_types_in_public_api
  _HoverWidgetState createState() => _HoverWidgetState();
}

class _HoverWidgetState extends State<HoverWidget> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return ArDriveTooltip(
      message: widget.tooltip ?? '',
      child: HoverDetector(
        cursor: SystemMouseCursors.click,
        onHover: () => setState(() => _isHovering = true),
        onExit: () => setState(() => _isHovering = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: Matrix4.identity()
            ..scale(_isHovering ? widget.hoverScale : 1.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5.0),
          ),
          child: Container(
            padding: widget.padding ?? const EdgeInsets.all(5.0),
            decoration: BoxDecoration(
              color: _isHovering
                  ? widget.hoverColor ??
                      ArDriveTheme.of(context)
                          .themeData
                          .colors
                          .themeBorderDefault
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(5.0),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class HoverDetector extends StatefulWidget {
  const HoverDetector({
    super.key,
    required this.onHover,
    required this.onExit,
    required this.child,
    this.cursor = SystemMouseCursors.click,
  });

  final Function() onHover;
  final Function() onExit;
  final Widget child;
  final SystemMouseCursor cursor;

  @override
  State<HoverDetector> createState() => _HoverDetectorState();
}

class _HoverDetectorState extends State<HoverDetector> {
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => widget.onHover(),
      onExit: (_) => widget.onExit(),
      child: widget.child,
    );
  }
}

class ArDriveIconButton extends StatelessWidget {
  const ArDriveIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 16,
    this.tooltip,
    this.scale,
  });

  final ArDriveIcon icon;
  final Function()? onPressed;
  final double size;
  final String? tooltip;
  final bool? scale;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: HoverWidget(
        tooltip: tooltip,
        hoverScale: scale == true ? 1.1 : 1.0,
        child: icon,
      ),
    );
  }
}
