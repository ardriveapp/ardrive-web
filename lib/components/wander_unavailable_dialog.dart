import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/services/arconnect/arconnect_prompt.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Says Wander could not be reached for a write or a private drive key, and
/// offers Try again, or Reconnect when Wander has lost ArDrive's
/// permissions. Resolves true to try again (or reconnect); Cancel, or
/// closing the dialog, resolves false.
///
/// If Wander answers after all while it is open, [answered] completes: the
/// dialog closes itself and this resolves true. It resolves then even if
/// the dialog could only be removed from under another route, where the
/// route's own future never completes; see [_WanderUnavailableDialogState].
Future<bool> askToRetryWander(
  BuildContext context,
  ArConnectUnavailableReason reason, {
  Future<void>? answered,
}) async {
  // Paired here rather than on the route: the route's future is not what
  // ends this when Wander answers.
  final activityTracker = context.read<ActivityTracker>();
  activityTracker.setShowingAnyDialog(true);
  try {
    final dialog = showAnimatedDialogWithBuilder<bool>(
      context,
      builder: (context) =>
          WanderUnavailableDialog(reason: reason, answered: answered),
    ).then((retry) => retry == true);
    return await Future.any([
      dialog,
      if (answered != null) answered.then((_) => true),
    ]);
  } finally {
    activityTracker.setShowingAnyDialog(false);
  }
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

  /// Wander answered after all. On top, the dialog pops. Under another
  /// route, such as the wallet-switch dialog, it is removed from under it;
  /// its route's future then never completes, which is why
  /// [askToRetryWander] races [WanderUnavailableDialog.answered] itself.
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
    final (title, description, retry) = switch (widget.reason) {
      ArConnectUnavailableReason.notInstalled => (
          l10n.wanderNotInstalledTitle,
          l10n.wanderNotInstalledDescription,
          l10n.tryAgainEmphasized,
        ),
      ArConnectUnavailableReason.noAnswer => (
          l10n.wanderNoAnswerTitle,
          l10n.wanderNoAnswerDescription,
          l10n.tryAgainEmphasized,
        ),
      ArConnectUnavailableReason.noPermission => (
          l10n.wanderNoPermissionTitle,
          null,
          l10n.wanderReconnect,
        ),
    };

    return ArDriveStandardModalNew(
      title: title,
      description: description,
      actions: [
        ModalAction(
          action: () => Navigator.of(context).pop(false),
          title: l10n.cancelEmphasized,
        ),
        ModalAction(
          action: () => Navigator.of(context).pop(true),
          title: retry,
        ),
      ],
    );
  }
}
