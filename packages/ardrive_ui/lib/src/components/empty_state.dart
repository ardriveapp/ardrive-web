import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// What a page, list or panel shows when it has nothing in it: an icon, a
/// heading, a line of text and an optional button, centred.
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
  });

  /// Drawn at 32 px in iconLow when it is an [ArDriveIcon] without its own
  /// size and colour.
  final Widget? icon;
  final String title;
  final String? message;

  /// The main thing to do next, as a primary button.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// A second, less important action, as a secondary button.
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Center(
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
                        onPressed: onSecondaryAction,
                      ),
                    if (actionLabel != null)
                      ArDriveButtonNew(
                        text: actionLabel!,
                        typography: typography,
                        variant: ButtonVariant.primary,
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
  }
}
