import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// A text link: underlined, darker on hover, reachable with the keyboard and
/// announced as a link.
///
/// Use it for anything that reads as a link, inside text or on its own. A
/// link that leaves the app sets [external], which adds the new-window icon.
/// Opening the address is the caller's: this package has no URL launcher.
class ArDriveLink extends StatefulWidget {
  const ArDriveLink({
    super.key,
    required this.text,
    required this.onTap,
    this.style,
    this.color,
    this.external = false,
    this.isAction = false,
  });

  final String text;
  final VoidCallback? onTap;

  /// The text style before the link's colour and underline. Defaults to
  /// paragraphNormal semiBold; pass the surrounding text's style when the link
  /// sits inside a sentence.
  final TextStyle? style;

  /// The link's colour at rest. Defaults to textMid; it is textHigh on hover.
  final Color? color;

  /// Whether the link opens outside the app, such as a website.
  final bool external;

  /// Whether the link does something, such as copying, rather than going
  /// somewhere. A screen reader then announces it as a button.
  final bool isAction;

  /// A link inside running text, laid on the text's baseline. It is a widget
  /// span so the link keeps its hover, focus and semantics.
  static InlineSpan span({
    required String text,
    required VoidCallback? onTap,
    TextStyle? style,
    Color? color,
    bool external = false,
  }) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: ArDriveLink(
        text: text,
        onTap: onTap,
        style: style,
        color: color,
        external: external,
      ),
    );
  }

  @override
  State<ArDriveLink> createState() => _ArDriveLinkState();
}

class _ArDriveLinkState extends State<ArDriveLink> {
  var _hovering = false;
  var _focused = false;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final enabled = widget.onTap != null;
    final color = !enabled
        ? colorTokens.textLow
        : _hovering || _focused
            ? colorTokens.textHigh
            : widget.color ?? colorTokens.textMid;
    final base = widget.style ??
        ArDriveTypographyNew.of(context)
            .paragraphNormal(fontWeight: ArFontWeight.semiBold);
    final style = base.copyWith(
      color: color,
      decoration: TextDecoration.underline,
      decorationColor: color,
    );

    Widget text = Text.rich(
      TextSpan(
        text: widget.text,
        children: [
          if (widget.external)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(left: ArDriveSpacing.xxs),
                child: ArDriveIcons.newWindow(
                  size: (style.fontSize ?? 14) * 1.1,
                  color: color,
                ),
              ),
            ),
        ],
      ),
      style: style,
    );

    // A link in monospace, such as a transaction ID, is given its final width
    // from the first frame, like [ArDriveIdText]: the face loads on demand,
    // and what sits beside the link stays put when it arrives.
    if (style.fontFamily == ArDriveMonospace.family) {
      final fontSize = style.fontSize ?? 13;
      final textScaler =
          MediaQuery.maybeOf(context)?.textScaler ?? TextScaler.noScaling;
      final iconWidth = widget.external
          ? ArDriveSpacing.xxs + textScaler.scale(fontSize * 1.1)
          : 0.0;
      text = SizedBox(
        width: ArDriveMonospace.widthOf(widget.text, fontSize,
                textScaler: textScaler) +
            iconWidth.ceilToDouble(),
        child: text,
      );
    }

    return Semantics(
      link: !widget.isAction,
      button: widget.isAction,
      enabled: enabled,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor:
            enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: CustomPaint(
              // The keyboard focus ring, drawn just outside the text so it takes
              // no room. Only the keyboard shows it: a click doesn't, as on the
              // web.
              foregroundPainter:
                  _focused ? _FocusRingPainter(colorTokens.strokeHigh) : null,
              child: text,
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusRingPainter extends CustomPainter {
  _FocusRingPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (Offset.zero & size).inflate(3),
        const Radius.circular(ArDriveRadius.sm),
      ),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_FocusRingPainter oldDelegate) =>
      oldDelegate.color != color;
}
