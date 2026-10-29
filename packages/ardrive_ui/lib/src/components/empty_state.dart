import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';

/// What a page, list or panel shows when it has nothing in it: an icon, a
/// heading, a line of text and an optional button, centred.
///
/// [framed] draws a dashed frame that fills the space it is given, for an
/// empty place files can be dropped onto.
class ArDriveEmptyState extends StatelessWidget {
  const ArDriveEmptyState({
    super.key,
    required this.title,
    this.icon,
    this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.framed = false,
  });

  /// Drawn at 32 px in iconLow when it is an [ArDriveIcon] without its own
  /// size and colour.
  final Widget? icon;
  final String title;
  final String? message;

  /// The main thing to do next, as a primary button. A label with a null
  /// [onAction] draws the button as unavailable.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// A second, less important action, as a secondary button. Unavailable,
  /// like the main one, when [onSecondaryAction] is null.
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  final bool framed;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ArDriveSpacing.md,
            vertical: ArDriveSpacing.xxl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                ExcludeSemantics(
                  child: switch (icon!) {
                    final ArDriveIcon i => i.copyWith(
                        size: i.size ?? 32,
                        color: i.color ?? colorTokens.iconLow,
                      ),
                    final other => other,
                  },
                ),
                const SizedBox(height: ArDriveSpacing.md),
              ],
              Text(
                title,
                textAlign: TextAlign.center,
                style: typography.heading5(
                  color: colorTokens.textHigh,
                  fontWeight: ArFontWeight.bold,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: ArDriveSpacing.xs),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: typography.paragraphNormal(color: colorTokens.textMid),
                ),
              ],
              if (actionLabel != null || secondaryActionLabel != null) ...[
                const SizedBox(height: ArDriveSpacing.lg),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: ArDriveSpacing.sm,
                  runSpacing: ArDriveSpacing.xs,
                  children: [
                    if (secondaryActionLabel != null)
                      ArDriveButtonNew(
                        text: secondaryActionLabel!,
                        typography: typography,
                        // ArDriveButtonNew colours itself off the flag alone,
                        // so a null callback without it looks live and does
                        // nothing.
                        isDisabled: onSecondaryAction == null,
                        onPressed: onSecondaryAction,
                      ),
                    if (actionLabel != null)
                      ArDriveButtonNew(
                        text: actionLabel!,
                        typography: typography,
                        variant: ButtonVariant.primary,
                        isDisabled: onAction == null,
                        onPressed: onAction,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (!framed) return content;

    return LayoutBuilder(
      builder: (context, constraints) => DottedBorder(
        borderType: BorderType.RRect,
        radius: const Radius.circular(12),
        color: colorTokens.strokeHigh,
        strokeWidth: 2,
        dashPattern: const [8, 6],
        padding: EdgeInsets.zero,
        child: SizedBox(
          width: constraints.hasBoundedWidth ? constraints.maxWidth : null,
          height: constraints.hasBoundedHeight ? constraints.maxHeight : null,
          // Scrolls rather than overflows when the frame is short.
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight:
                    constraints.hasBoundedHeight ? constraints.maxHeight : 0,
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}
