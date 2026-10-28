import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// One screen of the Turbo top-up, on the design system's standard dialog:
/// its red band, title, close button, spacing and action row.
///
/// Every top-up screen is built on this. They used to draw that chrome
/// themselves, each a copy with its own spacing and title size.
class TurboTopupScaffold extends StatelessWidget {
  const TurboTopupScaffold({
    super.key,
    required this.child,
    this.title,
    this.description,
    this.actions,
    this.onClose,
    this.canClose = true,
  });

  final Widget child;
  final String? title;

  /// A line under the title saying what this screen is for.
  final String? description;

  /// The dialog's action row: Back, and the screen's main action where it has
  /// one there.
  final List<ModalAction>? actions;

  /// What the close button does. Without one, it closes the dialog.
  final VoidCallback? onClose;

  /// Whether the screen offers a close button at all. Off while a payment is
  /// being processed.
  final bool canClose;

  static const double width = 575;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final description = this.description;

    return ArDriveStandardModalNew(
      title: title,
      width: width,
      hasCloseButton: canClose,
      close: onClose,
      scrollableContent: true,
      actions: actions,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (description != null) ...[
            Text(
              description,
              style: typography.paragraphNormal(color: colorTokens.textMid),
            ),
            const SizedBox(height: 24),
          ],
          child,
        ],
      ),
    );
  }
}
