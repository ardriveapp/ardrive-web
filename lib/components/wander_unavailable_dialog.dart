import 'package:ardrive/services/arconnect/arconnect_prompt.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// Says Wander could not be reached for a write or a private drive key, and
/// offers Try again. Resolves true to try again; Cancel, or closing the
/// dialog, resolves false.
///
/// If Wander answers after all while it is open, [answered] completes: the
/// dialog closes itself and this resolves true.
Future<bool> askToRetryWander(
  BuildContext context,
  ArConnectUnavailableReason reason, {
  Future<void>? answered,
}) async {
  var answeredFirst = false;
  answered?.then((_) => answeredFirst = true);

  final retry = await showArDriveDialogWithBuilder<bool>(
    context,
    builder: (context) =>
        WanderUnavailableDialog(reason: reason, answered: answered),
  );
  return answeredFirst || retry == true;
}

class WanderUnavailableDialog extends StatefulWidget {
  const WanderUnavailableDialog({
    super.key,
    required this.reason,
    this.answered,
  });

  final ArConnectUnavailableReason reason;

  /// Closes the dialog when it completes.
  final Future<void>? answered;

  @override
  State<WanderUnavailableDialog> createState() =>
      _WanderUnavailableDialogState();
}

class _WanderUnavailableDialogState extends State<WanderUnavailableDialog> {
  @override
  void initState() {
    super.initState();
    widget.answered?.then((_) => _closeOnAnswer());
  }

  void _closeOnAnswer() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    if (route.isCurrent) {
      Navigator.of(context).pop(true);
    } else {
      Navigator.of(context).removeRoute(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = appLocalizationsOf(context);
    final notInstalled =
        widget.reason == ArConnectUnavailableReason.notInstalled;

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
