import 'package:flutter/material.dart';

const double _defaultLoginCardMaxWidth = 512;
const double _defaultLoginCardMaxHeight = 489;

class MaxDeviceSizesConstrainedBox extends StatelessWidget {
  final double maxHeightPercent;
  final double defaultMaxHeight;
  final double defaultMaxWidth;
  final Widget child;

  const MaxDeviceSizesConstrainedBox({
    Key? key,
    this.maxHeightPercent = 0.8,
    this.defaultMaxWidth = _defaultLoginCardMaxWidth,
    this.defaultMaxHeight = _defaultLoginCardMaxHeight,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * maxHeightPercent;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: defaultMaxWidth,
        maxHeight: defaultMaxHeight > maxHeight ? maxHeight : defaultMaxHeight,
      ),
      child: child,
    );
  }
}
