import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CopyIconButton extends StatelessWidget {
  final String value;
  final String tooltip;
  final double? size;
  final Function? onTap;
  const CopyIconButton({
    Key? key,
    required this.value,
    required this.tooltip,
    this.size,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        Icons.copy,
        color: Colors.black54,
        size: size,
      ),
      tooltip: tooltip,
      onPressed: () {
        Clipboard.setData(ClipboardData(text: value));
        onTap?.call();
      },
    );
  }
}
