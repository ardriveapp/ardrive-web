import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
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

    // As far as it ever reached: this hung off the blocking modal, which only
    // a sync the user asked for ever raised. Off the modal it would otherwise
    // sit at the bottom of the window for the whole of every background sync
    // in dev and staging - the sync on login included, which is every session.
    final showsGateway = syncState is SyncInProgress &&
        syncState.trigger == SyncTrigger.userInitiated &&
        context.read<ConfigService>().flavor != Flavor.production;

    if (!showsGateway) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
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
