import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// A sentence in a share dialog that must be read before the link is sent.
///
/// The download dialog's treatment for its integrity warning: the icon and the
/// border carry the severity in `textRed`, and the sentence stays `textHigh`.
/// Small red text, which these were, is short of AA on the modal in both
/// themes, and in dark mode it was close to unreadable.
class ShareWarning extends StatelessWidget {
  const ShareWarning(
    this.text, {
    super.key,
    this.margin = const EdgeInsets.only(top: 12),
  });

  final String text;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Container(
      width: double.infinity,
      margin: margin,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorTokens.containerL1,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorTokens.textRed),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            // The sentence says everything the icon does.
            child: ExcludeSemantics(
              child: ArDriveIcons.triangle(
                size: 16,
                color: colorTokens.textRed,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: ArDriveTypographyNew.of(context).paragraphSmall(
                color: colorTokens.textHigh,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
