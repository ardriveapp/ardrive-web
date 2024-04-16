import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_ui/src/constants/size_constants.dart';
import 'package:flutter/material.dart';

enum ArDriveButtonStyle { primary, secondary, tertiary }

enum IconButtonAlignment { left, right }

class ArDriveButton extends StatefulWidget {
  const ArDriveButton({
    super.key,
    required this.text,
    this.onPressed,
    this.style = ArDriveButtonStyle.primary,
    this.backgroundColor,
    this.fontStyle,
    this.maxHeight,
    this.maxWidth,
    this.borderRadius,
    this.icon,
    this.isDisabled = false,
    this.iconAlignment = IconButtonAlignment.left,
    this.customContent,
  });

  final String text;
  final Function()? onPressed;
  final ArDriveButtonStyle style;
  final Color? backgroundColor;
  final TextStyle? fontStyle;
  final double? maxHeight;
  final double? maxWidth;
  final double? borderRadius;
  final bool isDisabled;
  final IconButtonAlignment iconAlignment;

  /// An optional icon to display to the left of the button text.
  /// Only applies to primary and secondary buttons.
  final Widget? icon;

  // An optional widget to display instead of the button text.
  // Only applies to primary
  final Widget? customContent;

  @override
  State<ArDriveButton> createState() => _ArDriveButtonState();
}

class _ArDriveButtonState extends State<ArDriveButton> {
  @override
  Widget build(BuildContext context) {
    switch (widget.style) {
      case ArDriveButtonStyle.primary:
        return SizedBox(
          height: widget.maxHeight ?? buttonDefaultHeight,
          width: widget.maxWidth,
          child: ElevatedButton(
            style: ButtonStyle(
              backgroundColor: _backgroundColor,
              maximumSize: _maxSize,
              shape: _shape,
              alignment: Alignment.center,
            ),
            onPressed: widget.isDisabled ? null : widget.onPressed,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null &&
                    widget.iconAlignment == IconButtonAlignment.left) ...[
                  widget.icon!,
                  const SizedBox(width: 8),
                ],
                widget.customContent ??
                    Text(
                      widget.text,
                      style: widget.fontStyle ??
                          ArDriveTypography.headline.headline5Bold(
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeFgOnAccent,
                          ),
                    ),
                if (widget.icon != null &&
                    widget.iconAlignment == IconButtonAlignment.right) ...[
                  const SizedBox(width: 8),
                  widget.icon!,
                ]
              ],
            ),
          ),
        );
      case ArDriveButtonStyle.secondary:
        return SizedBox(
          height: widget.maxHeight ?? buttonDefaultHeight,
          width: widget.maxWidth,
          child: OutlinedButton(
            onPressed: widget.isDisabled ? null : widget.onPressed,
            style: ButtonStyle(
              maximumSize: _maxSize,
              shape: _shapeOutlined,
              side: _borderSize,
              overlayColor: _overlayColor,
              alignment: Alignment.center,
              backgroundColor: _backgroundColor,
              foregroundColor: _backgroundColor,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null &&
                    widget.iconAlignment == IconButtonAlignment.left) ...[
                  widget.icon!,
                  const SizedBox(width: 8),
                ],
                Text(
                  widget.text,
                  style: widget.fontStyle ??
                      ArDriveTypography.headline.headline5Bold(
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgDefault,
                      ),
                ),
                if (widget.icon != null &&
                    widget.iconAlignment == IconButtonAlignment.right) ...[
                  const SizedBox(width: 8),
                  widget.icon!,
                ]
              ],
            ),
          ),
        );
      case ArDriveButtonStyle.tertiary:
        return ArDriveTextButton(
          text: widget.text,
          onPressed: widget.onPressed,
        );
    }
  }

  // overlay color for the secundary
  MaterialStateProperty<Color?> get _overlayColor =>
      MaterialStateProperty.resolveWith<Color?>(
        (Set<MaterialState> states) {
          final color = ArDriveTheme.of(context)
              .themeData
              .colors
              .themeFgDefault
              .withOpacity(0.1);

          return color;
        },
      );

  MaterialStateProperty<OutlinedBorder> get _shape =>
      MaterialStateProperty.resolveWith<OutlinedBorder>(
        (Set<MaterialState> states) {
          return RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              widget.borderRadius ?? buttonBorderRadius,
            ),
          );
        },
      );

  MaterialStateProperty<OutlinedBorder> get _shapeOutlined =>
      MaterialStateProperty.resolveWith<OutlinedBorder>(
        (Set<MaterialState> states) {
          return RoundedRectangleBorder(
            side: BorderSide(
              style: BorderStyle.solid,
              color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
            ),
            borderRadius: BorderRadius.circular(
              widget.borderRadius ?? buttonBorderRadius,
            ),
          );
        },
      );

  MaterialStateProperty<BorderSide?> get _borderSize =>
      MaterialStateProperty.resolveWith<BorderSide?>(
        (Set<MaterialState> states) {
          return BorderSide(
            width: buttonBorderWidth,
            style: BorderStyle.solid,
            color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
          );
        },
      );

  MaterialStateProperty<Size> get _maxSize =>
      MaterialStateProperty.resolveWith<Size>(
        (Set<MaterialState> states) {
          return const Size(buttonDefaultWidth, buttonDefaultHeight);
        },
      );

  MaterialStateProperty<Color?> get _backgroundColor =>
      MaterialStateProperty.resolveWith<Color?>(
        (Set<MaterialState> states) {
          if (widget.style == ArDriveButtonStyle.secondary) {
            return ArDriveTheme.of(context).themeData.colors.themeBgSurface;
          }

          if (widget.isDisabled) {
            return ArDriveTheme.of(context)
                .themeData
                .colors
                .themeAccentDisabled;
          }

          return widget.backgroundColor;
        },
      );
}

class ArDriveTextButton extends StatelessWidget {
  const ArDriveTextButton({
    super.key,
    required this.text,
    required this.onPressed,
  });
  final String text;
  final Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: ButtonStyle(overlayColor: _hoverColor),
      onPressed: onPressed,
      child: Text(
        text,
        style: ArDriveTypography.body.smallRegular().copyWith(
              decoration: TextDecoration.underline,
              color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
            ),
      ),
    );
  }

  MaterialStateProperty<Color?> get _hoverColor =>
      MaterialStateProperty.resolveWith<Color?>(
        (Set<MaterialState> states) {
          return Colors.transparent;
        },
      );
}
