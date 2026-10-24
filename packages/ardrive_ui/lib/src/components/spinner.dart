import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

enum ArDriveSpinnerSize {
  /// 16: inside a button, a row or next to a line of text.
  small(16, 2),

  /// 32: on its own, while a dialog, panel or page loads.
  large(32, 3);

  const ArDriveSpinnerSize(this.dimension, this.strokeWidth);

  final double dimension;
  final double strokeWidth;
}

/// Something is loading. Two sizes, one look.
class ArDriveSpinner extends StatelessWidget {
  const ArDriveSpinner({
    super.key,
    this.size = ArDriveSpinnerSize.small,
    this.color,
    this.value,
    this.semanticsLabel,
  });

  final ArDriveSpinnerSize size;

  /// Defaults to iconMid. Pass textOnPrimary on a primary button.
  final Color? color;

  /// Null spins; a value from 0 to 1 shows that much done.
  final double? value;

  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    return SizedBox.square(
      dimension: size.dimension,
      child: CircularProgressIndicator(
        value: value,
        strokeWidth: size.strokeWidth,
        strokeCap: StrokeCap.round,
        color: color ?? colorTokens.iconMid,
        backgroundColor: value == null ? null : colorTokens.strokeLow,
        semanticsLabel: semanticsLabel,
      ),
    );
  }
}

/// A progress bar: how far something has got, or that it is under way when
/// [value] is null.
class ArDriveLinearProgress extends StatelessWidget {
  const ArDriveLinearProgress({
    super.key,
    this.value,
    this.semanticsLabel,
  });

  /// From 0 to 1, or null when how far along isn't known.
  final double? value;

  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 4,
        color: colorTokens.buttonPrimaryDefault,
        backgroundColor: colorTokens.strokeMid,
        semanticsLabel: semanticsLabel,
      ),
    );
  }
}
