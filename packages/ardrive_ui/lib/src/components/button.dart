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
                      // Merged onto the default rather than replacing it, so
                      // a caller that only wants a different size or weight
                      // does not silently lose the colour. A `TextStyle` with
                      // a null colour inherits the button's `foregroundColor`,
                      // which for the secondary style is the surface colour -
                      // giving text the colour of the panel behind it. Merge
                      // keeps whatever the caller did set and fills the rest.
                      style: ArDriveTypography.headline
                          .headline5Bold(
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeFgOnAccent,
                          )
                          .merge(widget.fontStyle),
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
                  style: ArDriveTypography.headline
                      .headline5Bold(
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgDefault,
                      )
                      .merge(widget.fontStyle),
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

  /// The button's width. Null makes it as wide as its label, at least
  /// [minLabelWidth]; `double.infinity` fills the width it is given.
  ///
  /// A button used to fill whatever width it was given unless told otherwise,
  /// so a compact button under a line of text stretched across its card, and
  /// callers wrapped it in `IntrinsicWidth` or measured it to stop that.
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

  /// The width that fits [text] on one line in this button, and at least
  /// [minWidth].
  ///
  /// A button's width is fixed, so a label longer than the width it was given
  /// wraps inside it. Use this where the label can be longer than the usual
  /// width, such as one that names its action or counts files.
  static double fittedWidth(
    BuildContext context,
    String text, {
    required double minWidth,
    TextStyle? style,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: ArDriveTypographyNew.of(context)
            .paragraphLarge(fontWeight: ArFontWeight.semiBold)
            .merge(style),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();

    // The button's own padding is 10 on each side. The extra 8 covers what
    // this measure cannot see, such as letter spacing the button's theme
    // adds, and rounding.
    final width = painter.width + 28;
    painter.dispose();

    return width > minWidth ? width.ceilToDouble() : minWidth;
  }

  /// The narrowest a button sized to its label gets, so a short label such as
  /// "OK" still makes a button rather than a chip.
  static const double minLabelWidth = 100;

  @override
  State<ArDriveButtonNew> createState() => _ArDriveButtonNewState();
}

class _ArDriveButtonNewState extends State<ArDriveButtonNew> {
  var _hovering = false;

  /// The width that fits the label, for a button given none. Room is kept for
  /// an icon, and for the hover icon so the button doesn't grow under the
  /// pointer. Content that can't be measured fills, as before.
  double? _labelWidth(BuildContext context) {
    if (widget.customContent != null) return null;
    // The left icon is drawn over the label's row at 32-56, and the label is
    // centred in what the 24 px insets leave: 100 puts the label's left edge
    // at 64, 8 clear of the icon. A right icon, at 16 from the edge, clears a
    // centred label with 64.
    final icons = widget.icon != null
        ? 100
        : widget.rightIcon != null
            ? 64
            : 0;
    final hover = widget.hoverIcon != null ? 32 : 0;
    return ArDriveButtonNew.fittedWidth(
          context,
          widget.text,
          minWidth: ArDriveButtonNew.minLabelWidth,
          style: widget.fontStyle,
        ) +
        icons +
        hover;
  }

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
          // No vertical padding: the button centres its label, and padding
          // only took height from it. The label's line is 24 high, so at 10
          // above and below any button under 44 cut its descenders off.
          const EdgeInsets.symmetric(horizontal: 10)),
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
        // A label is one line in a box of its own height, so the style's line
        // height only added space, split in proportion to Wavehaus's tall
        // ascent: the capitals sat 1.9 px below the middle of the button.
        // Without it the font's own box is centred, 0.5 px off. (An even
        // leadingDistribution would do the same, but the web engine ignores
        // it.)
        textHeightBehavior: const TextHeightBehavior(
          applyHeightToFirstAscent: false,
          applyHeightToLastDescent: false,
        ),
        style: typography
            .paragraphLarge(
              color: foregroundColor,
              fontWeight: ArFontWeight.semiBold,
            )
            .copyWith(
              overflow: TextOverflow.ellipsis,
            )
            .merge(widget.fontStyle));

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
        width: widget.maxWidth ?? _labelWidth(context),
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
                          _hovering = hovering;
                        });
                      },
                style: style,
                child: widget.customContent != null
                    // Declared since this button was written and never drawn,
                    // so a caller that passed one silently got the plain
                    // label. Drawn in the TextButton's own centred child,
                    // which is what makes a spinner and its label read as one
                    // centred group - `icon` cannot, being pinned to the left
                    // edge in the stack below.
                    ? Center(child: widget.customContent!)
                    : widget.hoverIcon == null || isMobile(context)
                        ? text
                        // The icon joins the label on hover rather than
                        // replacing it. Sliding the label out left the button
                        // blank exactly when the pointer was on it, and blank
                        // behind a dialog the click had opened.
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              AnimatedSize(
                                duration: const Duration(milliseconds: 100),
                                child: _hovering && !widget.isDisabled
                                    ? Padding(
                                        padding:
                                            const EdgeInsets.only(right: 8),
                                        child: SizedBox.square(
                                          dimension: 24,
                                          child: widget.hoverIcon,
                                        ),
                                      )
                                    : const SizedBox(height: 24),
                              ),
                              Flexible(child: text),
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
