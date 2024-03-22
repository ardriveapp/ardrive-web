import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

enum ButtonVariant { primary, secondary, outline }

// FIXME: using this from ardrive_ui; move this class to ardrive_ui and remove
const double buttonDefaultHeight = 50;

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
    this.rightIcon,
    this.hoverIcon,
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
  final double borderRadius;
  final bool isDisabled;

  /// An optional icon to display to the left of the button text.
  /// Only applies to primary and secondary buttons.
  final Widget? icon;
  final Widget? rightIcon;

  final Widget? hoverIcon;

  // An optional widget to display instead of the button text.
  // Only applies to primary
  final Widget? customContent;

  @override
  State<ArDriveButtonNew> createState() => _ArDriveButtonState();
}

class _ArDriveButtonState extends State<ArDriveButtonNew> {
  var offsetY = 0.0;

  @override
  Widget build(BuildContext context) {
    var typography = widget.typography;
    var colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    Color defaultColor, hoverColor, pressedColor, foregroundColor;

    if (widget.isDisabled) {
      defaultColor = colorTokens.buttonDisabled;
      hoverColor = colorTokens.buttonDisabled;
      pressedColor = colorTokens.buttonDisabled;
      foregroundColor = colorTokens.textLow;
    } else if (widget.variant == ButtonVariant.primary) {
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
      shape: MaterialStatePropertyAll<RoundedRectangleBorder>(
          RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(widget.borderRadius)),
      )),
      alignment: Alignment.center,
      padding: MaterialStateProperty.all<EdgeInsetsGeometry>(
          const EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
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

    final text = Text(widget.text,
        textAlign: TextAlign.center,
        style: typography.paragraphLarge(
            color: foregroundColor, fontWeight: ArFontWeight.semiBold));

    final buttonH = widget.maxHeight ?? buttonDefaultHeight;

    return SizedBox(
        height: buttonH,
        width: widget.maxWidth,
        child: Stack(fit: StackFit.expand, children: [
          TextButton(
              onPressed: widget.isDisabled ? null : widget.onPressed,
              onHover: widget.hoverIcon == null
                  ? null
                  : (hovering) {
                      setState(() {
                        offsetY = hovering ? -1 : 0;
                      });
                    },
              style: style,
              child: widget.hoverIcon == null
                  ? text
                  : Stack(
                      fit: StackFit.expand,
                      alignment: Alignment.center,
                      children: [
                        AnimatedPositioned(
                            // FIXME: this is a hack to make the text align properly
                            // and will need to be updated for different typography
                            top: 12 + offsetY * buttonH,
                            duration: const Duration(milliseconds: 100),
                            child: SizedBox(height: buttonH, child: text)),
                        if (widget.hoverIcon != null)
                          AnimatedSlide(
                            offset: Offset(0, offsetY + 1),
                            duration: const Duration(milliseconds: 100),
                            child: widget.hoverIcon!,
                          )
                      ],
                    )),
          if (widget.rightIcon != null)
            Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 16),
              child: widget.rightIcon!,
            )
        ]));
  }
}
