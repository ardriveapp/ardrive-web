import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';

class ArDriveProgressBar extends StatefulWidget {
  const ArDriveProgressBar({
    super.key,
    required this.percentage,
    this.indicatorColor,
    this.backgroundColor,
    this.height = 15,
  });

  /// Should be a value between 0.0 and 1.0
  final double percentage;
  final Color? indicatorColor;
  final Color? backgroundColor;
  final double height;

  @override
  State<ArDriveProgressBar> createState() => _ArDriveProgressBarState();
}

class _ArDriveProgressBarState extends State<ArDriveProgressBar> {
  @override
  Widget build(BuildContext context) {
    return LinearPercentIndicator(
      animation: true,
      animateFromLastPercent: true,
      lineHeight: widget.height,
      barRadius: const Radius.circular(8),
      backgroundColor: widget.backgroundColor ??
          ArDriveTheme.of(context).themeData.colors.themeAccentSubtle,
      animationDuration: 1000,
      percent: widget.percentage,
      progressColor: widget.indicatorColor ??
          ArDriveTheme.of(context).themeData.colors.themeAccentMuted,
    );
  }
}
