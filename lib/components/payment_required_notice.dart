import 'package:ardrive/turbo/topup/views/topup_modal.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// What a dialog says, in itself, when Turbo turns its action down for
/// payment: the free upload allowance is used up. It replaces the dialog
/// that used to open over the form; Buy credits closes this dialog and opens
/// the top-up.
class PaymentRequiredNotice extends StatelessWidget {
  const PaymentRequiredNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = appLocalizationsOf(context);
    return ArDriveNotice(
      type: ArDriveNoticeType.error,
      title: l10n.freeAllowanceUsedUpTitle,
      message: l10n.freeAllowanceUsedUpDescription,
      actionLabel: l10n.buyCredits,
      onAction: () {
        Navigator.of(context).pop();
        showTurboTopupModal(context);
      },
    );
  }
}
