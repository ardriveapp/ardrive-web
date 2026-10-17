import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// A short warning set inline in a dialog, in the theme's warning colours.
///
/// The upload dialog's network congestion warning and its notes about keeping
/// the tab open use it, so they read as one kind of message. It always fills
/// the width it is given, so it looks the same in every dialog.
class InlineWarning extends StatelessWidget {
  const InlineWarning({
    super.key,
    required this.text,
    this.useNewArDriveUI = true,
  });

  final String text;

  /// Sets the text in the new typography, as the rest of the dialog does.
  final bool useNewArDriveUI;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.themeWarningSubtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colors.themeWarningEmphasis,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: colors.themeWarningEmphasis,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: useNewArDriveUI
                  ? typography.paragraphSmall(
                      color: colors.themeWarningFg,
                      fontWeight: ArFontWeight.semiBold,
                    )
                  : ArDriveTypography.body.smallBold(
                      color: colors.themeWarningFg,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
