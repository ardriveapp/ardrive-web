import 'dart:math';

import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// Says something brief at the foot of the screen and goes: a copied link, a
/// finished upload, a sync that failed. One look for all of them, floating
/// and at most 400 wide, coloured by [type] with the status set's icon, and an
/// optional action.
///
/// [messenger] rather than a context, so a caller can show it after the
/// dialog it came from has closed.
void showArDriveToast(
  ScaffoldMessengerState messenger, {
  required String text,
  ArDriveStatusType type = ArDriveStatusType.neutral,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 4),
}) {
  final colors = ArDriveTheme.of(messenger.context).themeData.colorTokens;
  final screenWidth = MediaQuery.sizeOf(messenger.context).width;

  final (Color container, Color stroke, Widget? icon) = switch (type) {
    ArDriveStatusType.neutral => (
        colors.containerRaised,
        colors.strokeMid,
        null
      ),
    ArDriveStatusType.info => (
        colors.statusInfoContainer,
        colors.statusInfoStroke,
        ArDriveIcons.info(size: 20, color: colors.statusInfoFg),
      ),
    ArDriveStatusType.warning => (
        colors.statusWarningContainer,
        colors.statusWarningStroke,
        ArDriveIcons.triangle(size: 20, color: colors.statusWarningFg),
      ),
    ArDriveStatusType.error => (
        colors.statusErrorContainer,
        colors.statusErrorStroke,
        ArDriveIcons.closeCircle(size: 20, color: colors.statusErrorFg),
      ),
    ArDriveStatusType.success => (
        colors.statusSuccessContainer,
        colors.statusSuccessStroke,
        ArDriveIcons.checkmark(size: 20, color: colors.statusSuccessFg),
      ),
  };

  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      width: min(screenWidth - 2 * ArDriveSpacing.md, 400),
      elevation: 0,
      backgroundColor: container,
      duration: duration,
      // A snackbar action, not a link in the text: Flutter keeps a snackbar
      // with an action up while a screen reader is on, so its user has time
      // to reach it.
      action: actionLabel == null || onAction == null
          ? null
          : SnackBarAction(
              label: actionLabel,
              textColor: colors.textHigh,
              onPressed: onAction,
            ),
      padding: const EdgeInsets.symmetric(
        horizontal: ArDriveSpacing.md,
        vertical: ArDriveSpacing.sm,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ArDriveRadius.md),
        side: BorderSide(color: stroke),
      ),
      // Typography reads the screen width, known where the toast shows.
      content: Builder(
        builder: (context) {
          final typography = ArDriveTypographyNew.of(context);
          return Semantics(
            liveRegion: true,
            child: Row(
              children: [
                if (icon != null) ...[
                  ExcludeSemantics(child: icon),
                  const SizedBox(width: ArDriveSpacing.sm),
                ],
                Expanded(
                  child: Text(
                    text,
                    style: typography.paragraphNormal(color: colors.textHigh),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
