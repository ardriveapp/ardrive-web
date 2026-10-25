import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// How ArDrive draws a markdown note: the file preview, and the note editor's
/// preview, which shows the note as it will look once saved.
///
/// [isFullScreen] is the reading size; the smaller one fits the preview card.
MarkdownStyleSheet arDriveMarkdownStyleSheet(
  ArdriveTypographyNew typography,
  ArDriveColorTokens colorTokens, {
  required bool isFullScreen,
}) {
  return MarkdownStyleSheet(
    p: isFullScreen
        ? typography
            .paragraphNormal(
              fontWeight: ArFontWeight.book,
              color: colorTokens.textHigh,
            )
            .copyWith(height: 1.8)
        : typography
            .paragraphSmall(
              fontWeight: ArFontWeight.book,
              color: colorTokens.textHigh,
            )
            .copyWith(height: 1.5),
    h1: isFullScreen
        ? typography.heading1(color: colorTokens.textHigh)
        : typography.heading3(color: colorTokens.textHigh),
    h2: isFullScreen
        ? typography.heading2(color: colorTokens.textHigh)
        : typography.heading4(color: colorTokens.textHigh),
    h3: isFullScreen
        ? typography.heading3(color: colorTokens.textHigh)
        : typography.heading5(color: colorTokens.textHigh),
    h4: isFullScreen
        ? typography.heading4(color: colorTokens.textHigh)
        : typography.heading6(color: colorTokens.textHigh),
    h5: typography.heading5(color: colorTokens.textHigh),
    h6: typography.heading6(color: colorTokens.textHigh),
    listBullet: typography.paragraphNormal(color: colorTokens.textHigh),
    // Set apart by its tint. It named Courier New, but the package's
    // type turned that into a family that does not exist, and the app
    // bundles no monospace face, so it was always Wavehaus.
    code: typography
        .paragraphSmall(
          fontWeight: ArFontWeight.book,
          color: colorTokens.textHigh,
        )
        .copyWith(backgroundColor: colorTokens.containerL2),
    codeblockDecoration: BoxDecoration(
      color: colorTokens.containerL2,
      borderRadius: BorderRadius.circular(ArDriveRadius.sm),
      border: Border.all(color: colorTokens.strokeLow),
    ),
    blockquote: typography
        .paragraphNormal(color: colorTokens.textMid)
        .copyWith(fontStyle: FontStyle.italic),
    blockquoteDecoration: BoxDecoration(
      border: Border(
        left: BorderSide(color: colorTokens.strokeHigh, width: 4),
      ),
    ),
    strong: typography
        .paragraphNormal(
          fontWeight: ArFontWeight.bold,
        )
        .copyWith(color: colorTokens.textHigh),
    em: typography.paragraphNormal().copyWith(
          fontStyle: FontStyle.italic,
          color: colorTokens.textHigh,
        ),
  );
}
