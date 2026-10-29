import 'package:ardrive/services/arconnect/arconnect_prompt.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// Says Wander could not be reached for a write or a private drive key, and
/// offers Try again. Resolves true to try again; Cancel, or closing the
/// dialog, resolves false.
Future<bool> askToRetryWander(
  BuildContext context,
  ArConnectUnavailableReason reason,
) async {
  final retry = await showArDriveDialogWithBuilder<bool>(
    context,
    builder: (context) => WanderUnavailableDialog(reason: reason),
  );
  return retry == true;
}

class WanderUnavailableDialog extends StatelessWidget {
  const WanderUnavailableDialog({super.key, required this.reason});

  final ArConnectUnavailableReason reason;

  @override
  Widget build(BuildContext context) {
    final l10n = appLocalizationsOf(context);
    final notInstalled = reason == ArConnectUnavailableReason.notInstalled;

    return ArDriveStandardModalNew(
      title: notInstalled
          ? l10n.wanderNotInstalledTitle
          : l10n.wanderNoAnswerTitle,
      description: notInstalled
          ? l10n.wanderNotInstalledDescription
          : l10n.wanderNoAnswerDescription,
      actions: [
        ModalAction(
          action: () => Navigator.of(context).pop(false),
          title: l10n.cancelEmphasized,
        ),
        ModalAction(
          action: () => Navigator.of(context).pop(true),
          title: l10n.tryAgainEmphasized,
        ),
      ],
    );
  }
}
