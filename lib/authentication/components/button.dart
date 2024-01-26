import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_ui/src/constants/size_constants.dart';
import 'package:flutter/material.dart';

enum ButtonVariant { primary, secondary, outline }

class ArDriveButtonNew extends StatefulWidget {
  const ArDriveButtonNew({
    super.key,
    required this.text,
    required this.typography,
    this.onPressed,
    this.variant = ButtonVariant.secondary,
    this.backgroundColor,
    this.fontStyle,
    this.maxHeight,
    this.maxWidth,
    this.borderRadius = 6,
    this.icon,
    this.isDisabled = false,
    this.customContent,
  });

  final String text;
  final ArdriveTypographyNew typography;
  final Function()? onPressed;
  final ButtonVariant variant;
  final Color? backgroundColor;
  final TextStyle? fontStyle;
  final double? maxHeight;
  final double? maxWidth;
  final double? borderRadius;
  final bool isDisabled;

  /// An optional icon to display to the left of the button text.
  /// Only applies to primary and secondary buttons.
  final Widget? icon;

  // An optional widget to display instead of the button text.
  // Only applies to primary
  final Widget? customContent;

  @override
  State<ArDriveButtonNew> createState() => _ArDriveButtonState();
}

class _ArDriveButtonState extends State<ArDriveButtonNew> {
  @override
  Widget build(BuildContext context) {
    var typography = widget.typography;
    var colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    Color defaultColor, hoverColor, pressedColor, foregroundColor;

    if (widget.variant == ButtonVariant.primary) {
      defaultColor = colorTokens.buttonPrimaryDefault;
      hoverColor = colorTokens.buttonPrimaryHover;
      pressedColor = colorTokens.buttonPrimaryPress;
      foregroundColor = colorTokens.textOnPrimary;
    } else if (widget.variant == ButtonVariant.secondary) {
      defaultColor = colorTokens.buttonSecondaryDefault;
      hoverColor = colorTokens.buttonSecondaryHover;
      pressedColor = colorTokens.buttonSecondaryPress;
      foregroundColor = colorTokens.textLink;
    } else {
      defaultColor = colorTokens.buttonOutlineDefault;
      hoverColor = colorTokens.buttonOutlineHover;
      pressedColor = colorTokens.buttonOutlinePress;
      foregroundColor = colorTokens.textLink;
    }

    var style = ButtonStyle(
      shape: const MaterialStatePropertyAll<RoundedRectangleBorder>(
          RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
      )),
      padding: MaterialStateProperty.all<EdgeInsetsGeometry>(
          const EdgeInsets.symmetric(horizontal: 48, vertical: 10)),
      backgroundColor: MaterialStateProperty.all<Color>(
          widget.backgroundColor ?? defaultColor),
      overlayColor:
          MaterialStateProperty.resolveWith<Color>((Set<MaterialState> states) {
        if (states.contains(MaterialState.hovered)) {
          return hoverColor;
        }
        if (states.contains(MaterialState.pressed)) {
          return pressedColor;
        }
        return hoverColor;
      }),
      side: widget.variant != ButtonVariant.outline
          ? null
          : MaterialStateProperty.resolveWith<BorderSide>(
              (Set<MaterialState> states) {
              return BorderSide(
                  color: states.contains(MaterialState.hovered) ||
                          states.contains(MaterialState.pressed)
                      ? colorTokens.strokeHigh
                      : colorTokens.strokeMid,
                  width: 1);
            }),
      foregroundColor: MaterialStateProperty.all<Color>(foregroundColor),
    );

    return SizedBox(
        height: widget.maxHeight ?? buttonDefaultHeight,
        width: widget.maxWidth,
        child: TextButton(
            onPressed: widget.onPressed,
            style: style,
            child: Text(widget.text,
                style: typography.paragraphLarge(
                    color: foregroundColor,
                    fontWeight: ArFontWeight.semiBold))));
  }
}
