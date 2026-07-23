import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// The free-tier status line shown above the payment method selector.
///
/// There is only ever one such line, so this renders all of its cases in one
/// place: the upload is free, the free allowance ran out, or there is nothing
/// to say. Keeping it in a single widget is what stops the upload, snapshot
/// and manifest dialogs from drifting apart — the manifest form previously
/// promised "free" without ever explaining what happened when it stopped
/// being free.
///
/// Renders nothing (and consumes no [padding]) for
/// [FreeUploadStatus.notEligible], where the payment selector alone is the
/// whole story.
class TurboFreeStatusMessage extends StatelessWidget {
  const TurboFreeStatusMessage({
    super.key,
    required this.status,
    this.padding = EdgeInsets.zero,
  });

  final FreeUploadStatus status;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    // notEligible has nothing to say — the payment selector alone is the whole
    // story — so render nothing and consume no padding.
    if (status == FreeUploadStatus.notEligible) {
      return const SizedBox.shrink();
    }

    final l10n = appLocalizationsOf(context);
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    // Exhaustive switch: adding a FreeUploadStatus becomes a compile error here
    // rather than a silently wrong message.
    final (String text, bool bold) = switch (status) {
      FreeUploadStatus.free => (l10n.freeTurboTransaction, true),
      FreeUploadStatus.exceedsAllowance => (
          l10n.freeAllowanceExceededUploadNote,
          false,
        ),
      FreeUploadStatus.allowanceUsedUp => (
          l10n.freeAllowanceUsedUpUploadNote,
          false,
        ),
      FreeUploadStatus.notEligible => ('', false), // handled above
    };

    return Padding(
      padding: padding,
      child: Text(
        text,
        style: typography.paragraphNormal(
          color: colorTokens.textMid,
          fontWeight: bold ? ArFontWeight.bold : ArFontWeight.book,
        ),
      ),
    );
  }
}
