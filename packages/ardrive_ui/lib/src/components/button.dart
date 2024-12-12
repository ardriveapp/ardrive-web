import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_ui/src/components/breakpoint_layout_builder.dart';
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
    this.rightIcon,
    this.hoverIcon,
    this.isDisabled = false,
    this.customContent,
    this.content,
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
  final Widget? content;

  /// An optional icon to display to the left of the button text.
  /// Only applies to primary and secondary buttons.
  final Widget? icon;
  final Widget? rightIcon;

  final Widget? hoverIcon;

  // An optional widget to display instead of the button text.
  // Only applies to primary
  final Widget? customContent;

  @override
  State<ArDriveButtonNew> createState() => _ArDriveButtonNewState();
}

class _ArDriveButtonNewState extends State<ArDriveButtonNew> {
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
        style: widget.fontStyle ??
            typography
                .paragraphLarge(
                  color: foregroundColor,
                  fontWeight: ArFontWeight.semiBold,
                )
                .copyWith(
                  overflow: TextOverflow.ellipsis,
                ));

    final buttonH = widget.maxHeight ?? buttonDefaultHeight;

    if (widget.content != null) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: widget.maxWidth ?? double.infinity,
          maxHeight: buttonH,
        ),
        child: TextButton(
          onPressed: widget.onPressed,
          style: style,
          child: widget.content!,
        ),
      );
    }

    return SizedBox(
        height: buttonH,
        width: widget.maxWidth,
        child: Stack(fit: StackFit.expand, children: [
          Padding(
            padding: EdgeInsets.only(
                left: widget.icon != null ? 24 : 0,
                right: widget.icon != null ? 24 : 0),
            child: TextButton(
                onPressed: widget.isDisabled ? null : widget.onPressed,
                onHover: widget.hoverIcon == null || isMobile(context)
                    ? null
                    : (hovering) {
                        setState(() {
                          offsetY = hovering ? -1 : 0;
                        });
                      },
                style: style,
                child: widget.hoverIcon == null || isMobile(context)
                    ? isMobile(context) && buttonH < 45
                        ? Transform.translate(
                            offset: const Offset(0, -2), child: text)
                        : text
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
          ),
          if (widget.icon != null)
            Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 32),
              child: widget.icon!,
            ),
          if (widget.rightIcon != null)
            Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 16),
              child: widget.rightIcon!,
            )
        ]));
  }
}
