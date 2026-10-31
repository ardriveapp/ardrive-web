import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Reports a failed sync as a toast where there is no sync indicator to
/// report it on.
///
/// The top bar's indicator is where a failure is said, once, with a Try again
/// that repeats what failed. A publication has no indicator (its top bar
/// carries no sync control), so without this a failure there would be said
/// nowhere. Where the indicator is on screen this stays out of the way, so one
/// failure is still reported once.
class SyncFailureToastListener extends StatelessWidget {
  const SyncFailureToastListener({
    super.key,
    required this.enabled,
    required this.child,
  });

  /// Whether no sync indicator is on screen to report the failure instead.
  final bool enabled;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    return BlocListener<SyncCubit, SyncState>(
      listenWhen: (previous, current) => current is SyncFailure,
      listener: (context, state) {
        final failure = state as SyncFailure;
        final l10n = appLocalizationsOf(context);
        showArDriveToast(
          ScaffoldMessenger.of(context),
          text: failure.kind == SyncFailureKind.sync
              ? l10n.syncStoppedWithError
              : l10n.syncFailed,
          type: ArDriveStatusType.error,
          actionLabel: l10n.tryAgain,
          onAction: () => context.read<SyncCubit>().retryFailure(),
        );
      },
      child: child,
    );
  }
}
