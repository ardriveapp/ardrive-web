import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

class HoverWidget extends StatefulWidget {
  final Widget child;
  final double hoverScale;
  final Color hoverColor;
  final Color? backgroundColor;
  final String? tooltip;

  const HoverWidget({
    super.key,
    required this.child,
    this.hoverScale = 1.1,
    this.hoverColor = Colors.transparent,
    this.backgroundColor,
    this.tooltip,
  });

  @override
  // ignore: library_private_types_in_public_api
  _HoverWidgetState createState() => _HoverWidgetState();
}

class _HoverWidgetState extends State<HoverWidget> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip ?? '',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: Matrix4.identity()
            ..scale(_isHovering ? widget.hoverScale : 1.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5.0),
          ),
          child: Container(
            padding: const EdgeInsets.all(5.0),
            decoration: BoxDecoration(
              color: _isHovering
                  ? widget.backgroundColor ??
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

class ArDriveIconButton extends StatelessWidget {
  const ArDriveIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 16,
    this.tooltip,
  });

  final ArDriveIcon icon;
  final Function()? onPressed;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: HoverWidget(
        tooltip: tooltip,
        child: icon,
      ),
    );
  }
}
