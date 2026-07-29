import 'package:ardrive/turbo/topup/views/topup_modal.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// Shown when an operation is rejected by Turbo for payment reasons — the
/// free allowance is used up (or credits are insufficient), so the action
/// now requires Credits.
///
/// Single source of truth for this message and its "Add Credits" action, so
/// every metadata/upload path presents the same UX. Purely informational —
/// the caller has already dismissed its own progress UI before calling this.
void showTurboPaymentRequiredDialog(BuildContext context) {
  showArDriveDialog(
    context,
    content: ArDriveStandardModalNew(
      title: appLocalizationsOf(context).freeAllowanceUsedUpTitle,
      description: appLocalizationsOf(context).freeAllowanceUsedUpDescription,
      actions: [
        ModalAction(
          action: () => Navigator.of(context).pop(),
          title: appLocalizationsOf(context).cancel,
        ),
        ModalAction(
          action: () {
            Navigator.of(context).pop();
            showTurboTopupModal(context);
          },
          title: appLocalizationsOf(context).buyCredits,
        ),
      ],
    ),
  );
}
