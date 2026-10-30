import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_ui/src/components/breakpoint_layout_builder.dart';
import 'package:flutter/material.dart';

enum ButtonVariant { primary, secondary, outline }

/// The three heights a button comes in. Pick by where the button sits, not by
/// what fits: every button in the same place is the same height.
enum ArDriveButtonSize {
  /// 36: inside a card, banner, list row or notice.
  compact(36),

  /// 40: dialog actions, toolbars, and anywhere else by default.
  regular(40),

  /// 48: a full-width button that is the main action of a page, such as
  /// sign-in or an empty page.
  large(48);

  const ArDriveButtonSize(this.height);

  final double height;
}

const double _externalIconSize = 16;
const double _externalIconWidth = _externalIconSize + ArDriveSpacing.xxs;

class ArDriveButtonNew extends StatefulWidget {
  const ArDriveButtonNew({
    super.key,
    required this.text,
    required this.typography,
    this.onPressed,
    this.variant = ButtonVariant.secondary,
    this.backgroundColor,
    this.fontStyle,
    this.size = ArDriveButtonSize.regular,
    this.maxWidth,
    this.borderRadius = ArDriveRadius.control,
    this.icon,
    this.rightIcon,
    this.hoverIcon,
    this.isDisabled = false,
    this.customContent,
    this.content,
    this.external = false,
  });

  final String text;
  final ArdriveTypographyNew typography;
  final Function()? onPressed;
  final ButtonVariant variant;
  final Color? backgroundColor;
  final TextStyle? fontStyle;

  /// The button's height. There are three, and nothing else sets one.
  final ArDriveButtonSize size;

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

  /// Opens a page outside the app, in a new window: the standard new-window
  /// icon follows the label, as on [ArDriveLink.external].
  final bool external;

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
    // A left icon sits 8 px before the label and is centred with it as one
    // group, so it adds its width (up to 24) and the gap. A right icon, at 16
    // from the edge, clears a centred group with 64. With both, both apply.
    final icons = (widget.icon != null ? 32 : 0) +
        (widget.rightIcon != null ? 64 : 0) +
        (widget.external ? _externalIconWidth : 0);
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

  /// Whether the button has focus from the keyboard, which draws the ring.
  bool _keyboardFocused = false;

  @override
  Widget build(BuildContext context) {
    // Material's button takes focus but draws no ring we can see, so Tab
    // landed on a button with no sign it had. Only the keyboard shows it.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onFocusChange: (focused) => setState(() => _keyboardFocused = focused &&
          FocusManager.instance.highlightMode ==
              FocusHighlightMode.traditional),
      child: CustomPaint(
        foregroundPainter: _keyboardFocused
            ? ArDriveFocusRingPainter(
                ArDriveTheme.of(context).themeData.colorTokens.focusRing,
                radius: widget.borderRadius + 2,
              )
            : null,
        child: _button(context),
      ),
    );
  }

  Widget _button(BuildContext context) {
    var typography = widget.typography;
    var colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    Color defaultColor, hoverColor, pressedColor, foregroundColor;

    if (widget.isDisabled) {
      defaultColor = colorTokens.buttonDisabled;
      hoverColor = colorTokens.buttonDisabled;
      pressedColor = colorTokens.buttonDisabled;
      foregroundColor = colorTokens.textXLow;
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

    final label = Text(widget.text,
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

    // The new-window icon follows the label and stays with it when the label
    // is cut short.
    final Widget text = !widget.external
        ? label
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: label),
              const SizedBox(width: ArDriveSpacing.xxs),
              ExcludeSemantics(
                child: ArDriveIcons.newWindow(
                  size: _externalIconSize,
                  color: foregroundColor,
                ),
              ),
            ],
          );

    final buttonH = widget.size.height;

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
          // The fill spans the whole button, icon or not, so a full-width
          // button with an icon lines up with everything else in its column.
          // It was inset 24 px on each side when it had an icon.
          TextButton(
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
                      ? widget.icon == null
                          ? text
                          // The icon and label are one group, centred
                          // together, at any width.
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                widget.icon!,
                                const SizedBox(width: 8),
                                Flexible(child: text),
                              ],
                            )
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
                                      padding: const EdgeInsets.only(right: 8),
                                      child: SizedBox.square(
                                        dimension: 24,
                                        child: widget.hoverIcon,
                                      ),
                                    )
                                  : const SizedBox(height: 24),
                            ),
                            // The icon stays, hovered or not; the hover icon
                            // only joins it.
                            if (widget.icon != null) ...[
                              widget.icon!,
                              const SizedBox(width: 8),
                            ],
                            Flexible(child: text),
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
