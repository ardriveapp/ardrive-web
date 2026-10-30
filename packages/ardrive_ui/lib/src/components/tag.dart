import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

enum ArDriveTagType {
  /// A plain label: "Shared with me", "Controller".
  neutral,

  /// Brand Info: something to know about the item.
  info,

  /// Brand Success: something that worked, such as a discount applied.
  success,
}

/// A small label beside an item's name: one shape everywhere, the
/// explorer's caption on a quiet fill.
///
/// No warning or error tag: a warning or an error is not a label on an item,
/// it is something to read, so it is [ArDriveStatusText] (or an
/// [ArDriveNotice] when it needs room).
class ArDriveTag extends StatelessWidget {
  const ArDriveTag({
    super.key,
    this.text,
    this.type = ArDriveTagType.neutral,
    this.icon,
    this.foregroundColor,
    this.backgroundColor,
  }) : assert(text != null || icon != null, 'A tag needs text or an icon');

  /// The label; ellipsized when the tag is given less room than it needs.
  /// Null for an icon-only tag.
  final String? text;
  final ArDriveTagType type;

  /// An optional leading icon, drawn in the text's colour.
  final IconData? icon;

  /// Overrides for a surface that has its own contrast tokens, such as the
  /// shared file page. Everywhere else the [type] decides the colours.
  final Color? foregroundColor;
  final Color? backgroundColor;

  static const iconSize = 12.0;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final (fg, fill) = switch (type) {
      ArDriveTagType.neutral => (colorTokens.textMid, colorTokens.containerL3),
      ArDriveTagType.info => (
          colorTokens.statusInfoFg,
          colorTokens.statusInfoContainer,
        ),
      ArDriveTagType.success => (
          colorTokens.statusSuccessFg,
          colorTokens.statusSuccessContainer,
        ),
    };
    final color = foregroundColor ?? fg;
    final text = this.text;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ArDriveSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: backgroundColor ?? fill,
        borderRadius: BorderRadius.circular(ArDriveRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            ExcludeSemantics(
              child: Icon(icon, size: iconSize, color: color),
            ),
          if (icon != null && text != null)
            const SizedBox(width: ArDriveSpacing.xxs),
          if (text != null)
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: typography.caption(
                  color: color,
                  fontWeight: ArFontWeight.semiBold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum ArDriveStatusType {
  /// Words alone, in the quiet text colour: "Checking", "Not checked".
  neutral,

  /// Brand Info.
  info,

  /// Neutral text with the warning icon: the brand has no warning colour.
  warning,

  /// The brand reds: something wrong or about to be lost.
  error,

  /// Brand Success.
  success,
}

/// A status said in a line of text with its icon: "Lease ends in 12 days",
/// "Verified", "2 drives could not be read".
///
/// The colours follow [ArDriveNotice]: an error in the error colour, info and
/// success in theirs, and a warning in neutral text with the warning icon
/// carrying the meaning. Each type has its own icon, so the meaning never
/// rests on colour alone.
class ArDriveStatusText extends StatelessWidget {
  const ArDriveStatusText({
    super.key,
    required this.text,
    required this.type,
    this.style,
    this.maxLines,
    this.color,
    this.iconColor,
  });

  final String text;
  final ArDriveStatusType type;

  /// The text's style, its colour replaced; `paragraphSmall` by default.
  final TextStyle? style;
  final int? maxLines;

  /// Overrides for a surface that has its own contrast tokens, such as the
  /// shared file page.
  final Color? color;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final fg = color ??
        switch (type) {
          ArDriveStatusType.neutral => colorTokens.textMid,
          ArDriveStatusType.info => colorTokens.statusInfoFg,
          ArDriveStatusType.warning => colorTokens.textMid,
          ArDriveStatusType.error => colorTokens.statusErrorFg,
          ArDriveStatusType.success => colorTokens.statusSuccessFg,
        };
    final textStyle = (style ?? typography.paragraphSmall()).copyWith(
      color: fg,
    );
    final iconSize = (textStyle.fontSize ?? 14) + 2;
    final ic = iconColor ?? fg;
    final icon = switch (type) {
      ArDriveStatusType.neutral => null,
      ArDriveStatusType.info => ArDriveIcons.info(size: iconSize, color: ic),
      ArDriveStatusType.warning =>
        ArDriveIcons.triangle(size: iconSize, color: ic),
      ArDriveStatusType.error =>
        ArDriveIcons.closeCircle(size: iconSize, color: ic),
      ArDriveStatusType.success =>
        ArDriveIcons.checkCirle(size: iconSize, color: ic),
    };

    return MergeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            ExcludeSemantics(child: icon),
            const SizedBox(width: ArDriveSpacing.xxs),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: maxLines,
              overflow: maxLines == null ? null : TextOverflow.ellipsis,
              style: textStyle,
            ),
          ),
        ],
      ),
    );
  }
}
