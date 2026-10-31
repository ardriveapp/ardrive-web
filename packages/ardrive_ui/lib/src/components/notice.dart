import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

enum ArDriveNoticeType { info, warning, error, success }

enum ArDriveNoticeLayout {
  /// A rounded box inside a dialog, card or page.
  inline,

  /// A full-width strip across the top of a page, with no corners and a line
  /// under it.
  banner,
}

/// A message with a meaning: something to know, to watch out for, that went
/// wrong, or that worked.
///
/// One notice style for the whole app: an icon in the status colour on a
/// tinted surface, the text in the normal text colour, and an optional action
/// and close button.
class ArDriveNotice extends StatelessWidget {
  const ArDriveNotice({
    super.key,
    required this.type,
    this.message,
    this.content,
    this.title,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
    this.dismissLabel = 'Dismiss',
    this.layout = ArDriveNoticeLayout.inline,
    this.leading,
  }) : assert(message != null || content != null,
            'A notice needs a message or content');

  final ArDriveNoticeType type;

  /// The notice's text. Use [content] instead for text with links in it.
  final String? message;

  /// Shown in place of [message], for text that needs more than a string.
  final Widget? content;

  /// An optional bold first line.
  final String? title;

  /// An optional button, such as "Retry", shown after the text.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Shows a close button when set.
  final VoidCallback? onDismiss;

  /// The close button's tooltip and screen reader label.
  final String dismissLabel;

  final ArDriveNoticeLayout layout;

  /// Shown in place of the type's icon, for a notice whose state is still
  /// changing, such as a small [ArDriveSpinner] while what it reports runs.
  /// Keep it to 20 px, the icon's size, so the text does not move when it is
  /// swapped back for the icon.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final (fg, container, stroke) = switch (type) {
      ArDriveNoticeType.info => (
          colorTokens.statusInfoFg,
          colorTokens.statusInfoContainer,
          colorTokens.statusInfoStroke,
        ),
      ArDriveNoticeType.warning => (
          colorTokens.statusWarningFg,
          colorTokens.statusWarningContainer,
          colorTokens.statusWarningStroke,
        ),
      ArDriveNoticeType.error => (
          colorTokens.statusErrorFg,
          colorTokens.statusErrorContainer,
          colorTokens.statusErrorStroke,
        ),
      ArDriveNoticeType.success => (
          colorTokens.statusSuccessFg,
          colorTokens.statusSuccessContainer,
          colorTokens.statusSuccessStroke,
        ),
    };
    final icon = switch (type) {
      // Each type has its own icon, so the meaning doesn't rest on colour
      // alone: a warning is neutral and an error is red, but a reader who
      // can't tell them apart by colour can by shape.
      ArDriveNoticeType.info => ArDriveIcons.info(size: 20, color: fg),
      ArDriveNoticeType.warning => ArDriveIcons.triangle(size: 20, color: fg),
      ArDriveNoticeType.error => ArDriveIcons.closeCircle(size: 20, color: fg),
      ArDriveNoticeType.success => ArDriveIcons.checkCirle(size: 20, color: fg),
    };
    final isBanner = layout == ArDriveNoticeLayout.banner;

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(bottom: ArDriveSpacing.xxs),
            child: Text(
              title!,
              style: typography.paragraphNormal(
                color: colorTokens.textHigh,
                fontWeight: ArFontWeight.semiBold,
              ),
            ),
          ),
        DefaultTextStyle.merge(
          style: typography.paragraphNormal(color: colorTokens.textHigh),
          child: content ?? Text(message!),
        ),
      ],
    );

    final action = actionLabel == null
        ? null
        : ArDriveButtonNew(
            text: actionLabel!,
            typography: typography,
            variant: ButtonVariant.outline,
            size: ArDriveButtonSize.compact,
            // A withdrawn action looks disabled as well as doing nothing.
            isDisabled: onAction == null,
            onPressed: onAction,
          );

    return Semantics(
      container: true,
      liveRegion: type == ArDriveNoticeType.error,
      child: Container(
        width: isBanner ? double.infinity : null,
        padding: EdgeInsets.symmetric(
          horizontal: isBanner ? ArDriveSpacing.md : ArDriveSpacing.sm,
          vertical: ArDriveSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: container,
          borderRadius:
              isBanner ? null : BorderRadius.circular(ArDriveRadius.md),
          border: isBanner
              ? Border(bottom: BorderSide(color: stroke))
              : Border.all(color: stroke),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Lines the icon up with the first line of text.
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: ExcludeSemantics(
                child: leading == null
                    ? icon
                    : SizedBox.square(
                        dimension: 20,
                        child: Center(child: leading),
                      ),
              ),
            ),
            const SizedBox(width: ArDriveSpacing.sm),
            Expanded(
              child: action == null
                  ? text
                  // The action follows the text, and drops under it when
                  // the two don't fit on one line.
                  : Wrap(
                      spacing: ArDriveSpacing.sm,
                      runSpacing: ArDriveSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      alignment: WrapAlignment.spaceBetween,
                      children: [text, action],
                    ),
            ),
            if (onDismiss != null) ...[
              const SizedBox(width: ArDriveSpacing.xs),
              Tooltip(
                message: dismissLabel,
                child: Semantics(
                  button: true,
                  label: dismissLabel,
                  child: InkWell(
                    onTap: onDismiss,
                    borderRadius: BorderRadius.circular(ArDriveRadius.sm),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: ArDriveIcons.x(
                        size: 18,
                        color: colorTokens.iconMid,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
