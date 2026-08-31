import 'dart:async';

import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/presentation/sync_summary.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Everything the shell still paints on top of the app because of a sync,
/// which is now one thing: what a sync the user asked for found, for a few
/// seconds, over an app that stays usable throughout.
///
/// Nothing here blocks. The modal a user-initiated sync used to hold - a
/// scrim, a title, a phase line, a bar and a percentage, with no action of its
/// own - is gone: the top bar's ring says a sync is running, a tap on it says
/// which sync and how far it has got, and the sync history in the
/// Troubleshooting modal says what every recent one did. Every other state
/// reports at the top bar's [SyncButton], where the sync was running.
class SyncOverlay extends StatelessWidget {
  const SyncOverlay({
    super.key,
    required this.syncState,
  });

  final SyncState syncState;

  @override
  Widget build(BuildContext context) {
    // Read into a local so the `is` check below promotes it.
    final syncState = this.syncState;

    final showsSummary = syncState is SyncComplete &&
        // A sync nobody asked for reports at the top bar's indicator, where it
        // was running. It never interrupted the user and its result must not
        // either.
        syncState.trigger == SyncTrigger.userInitiated &&
        // A result the user has already been shown, or missed entirely, is not
        // announced again just because this widget was rebuilt - see
        // [syncSummaryIsFresh].
        syncSummaryIsFresh(syncState);

    // As far as it ever reached: this hung off the blocking modal, which only
    // a sync the user asked for ever raised. Off the modal it would otherwise
    // sit at the bottom of the window for the whole of every background sync
    // in dev and staging - the sync on login included, which is every session.
    final showsGateway = syncState is SyncInProgress &&
        syncState.trigger == SyncTrigger.userInitiated &&
        context.read<ConfigService>().flavor != Flavor.production;

    if (!showsSummary && !showsGateway) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        if (showsSummary) SyncCompleteSummary(state: syncState),
        // A debug affordance, and the only reason this widget still draws
        // anything while a sync runs.
        if (showsGateway)
          Positioned(
            bottom: 0,
            right: 20,
            child: Text(
              'Using gateway: ${context.read<ConfigService>().config.arweaveGatewayForDataRequest.url}',
              style: ArDriveTypographyNew.of(context).paragraphLarge(
                fontWeight: ArFontWeight.semiBold,
              ),
            ),
          ),
      ],
    );
  }
}

/// The last thing a sync the user asked for shows: what it found, and then
/// nothing.
///
/// Drawn without a scrim and without a barrier: there is no question to answer
/// here, so the app is usable underneath from the moment the summary appears,
/// and it takes itself away after [syncSummaryDuration].
class SyncCompleteSummary extends StatefulWidget {
  const SyncCompleteSummary({super.key, required this.state});

  final SyncComplete state;

  @override
  State<SyncCompleteSummary> createState() => _SyncCompleteSummaryState();
}

class _SyncCompleteSummaryState extends State<SyncCompleteSummary> {
  Timer? _dismiss;
  bool _showing = true;

  @override
  void initState() {
    super.initState();
    _countDown();
  }

  @override
  void didUpdateWidget(covariant SyncCompleteSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A second sync finishing is a second result, even when it reads the same
    // as the first one - so it gets shown again, and its own few seconds.
    if (widget.state.sequence != oldWidget.state.sequence) {
      setState(() => _showing = true);
      _countDown();
    }
  }

  void _countDown() {
    _dismiss?.cancel();
    _dismiss = Timer(syncSummaryRemaining(widget.state), () {
      if (mounted) {
        setState(() => _showing = false);
      }
    });
  }

  @override
  void dispose() {
    _dismiss?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_showing) {
      return const SizedBox.shrink();
    }

    final typography = ArDriveTypographyNew.of(context);

    // Nothing here is clickable, and the app behind it is: the summary must
    // not eat a click aimed at the drive the user came back to.
    return IgnorePointer(
      child: Align(
        alignment: Alignment.center,
        child: Material(
          borderRadius: BorderRadius.circular(8),
          child: ArDriveStandardModalNew(
            title: appLocalizationsOf(context).syncComplete,
            content: Text(
              syncCompleteSummary(appLocalizationsOf(context), widget.state),
              style: typography.paragraphNormal(),
            ),
          ),
        ),
      ),
    );
  }
}
