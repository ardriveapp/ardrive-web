import 'package:flutter/material.dart';

class ArDriveClickArea extends StatelessWidget {
  const ArDriveClickArea({
    super.key,
    required this.child,
    this.showCursor = true,
    this.tooltip,
  });

  final Widget child;
  final bool showCursor;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: MouseRegion(
        cursor:
            showCursor ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: child,
      ),
    );
  }
}
