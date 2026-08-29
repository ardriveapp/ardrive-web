import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/components/progress_bar.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/sync/presentation/sync_summary.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Everything the shell paints on top of the app because of a sync.
///
/// A sync the user asked for keeps the app to itself: a scrim over the whole
/// window and a modal on top of it. A sync that merely happened - the one that
/// runs on login - paints nothing here at all, so the user can keep browsing,
/// opening drives and uploading while it runs; the top bar's [SyncButton] is
/// the only place it shows up.
///
/// Errors follow the same rule. A failure the user was waiting on keeps the
/// modal it was already holding, retry button and all. A failure from a sync
/// nobody asked for does not seize the screen to ask a question the user has
/// no context for - it reports at the top bar's [SyncButton], where the sync
/// was running, and keeps Retry reachable in that button's menu.
class SyncOverlay extends StatelessWidget {
  const SyncOverlay({
    super.key,
    required this.syncState,
  });

  final SyncState syncState;

  /// Whether [state] is a sync that gets to hold the whole app.
  ///
  /// [SyncLoadingDrives] is not one of them, though it is the cubit's initial
  /// state and the metadata-only login path: both are syncs nobody asked for,
  /// and the drives list they refresh is already on screen from the local
  /// database. The top bar's indicator says it is happening.
  static bool blocksTheApp(SyncState state) {
    // A finished sync reports itself and gets out of the way, whoever asked
    // for it. The summary the user-initiated one ends on is drawn without a
    // scrim and dismisses itself, so a sync that used to end in silence never
    // starts costing a click.
    if (state is SyncComplete) {
      return false;
    }
    // Errors used to be the one terminal state with no trigger to honour, so
    // a login sync that painted nothing while it ran would still drop a scrim
    // and "Sync Incomplete" over whatever the user was in the middle of the
    // moment one drive out of several failed. It reports at the top bar now.
    if (state is SyncCompleteWithErrors) {
      return state.trigger == SyncTrigger.userInitiated;
    }
    if (state is SyncInProgress) {
      return state.trigger == SyncTrigger.userInitiated;
    }
    if (state is SyncCancelled) {
      return state.trigger == SyncTrigger.userInitiated;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    // Read into a local so the `is` checks below promote it.
    final syncState = this.syncState;

    if (syncState is SyncComplete) {
      // The sync the user asked for is already holding a modal; it ends on its
      // result rather than vanishing. A sync nobody asked for was never here,
      // and reports at the top bar's indicator instead.
      if (syncState.trigger != SyncTrigger.userInitiated) {
        return const SizedBox.shrink();
      }

      // A result the user has already been shown, or missed entirely, is not
      // announced again just because this widget was rebuilt - see
      // [syncSummaryIsFresh].
      if (!syncSummaryIsFresh(syncState)) {
        return const SizedBox.shrink();
      }

      return SyncCompleteSummary(state: syncState);
    }

    if (!blocksTheApp(syncState)) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        const SyncScrim(),
        BlocBuilder<ProfileCubit, ProfileState>(
          builder: (context, state) {
            final typography = ArDriveTypographyNew.of(context);
            return FutureBuilder(
              future: context.read<ProfileCubit>().isCurrentProfileArConnect(),
              builder: (BuildContext context, AsyncSnapshot snapshot) {
                final isCurrentProfileArConnect = snapshot.data == true;

                if (syncState is SyncCancelled) {
                  return Align(
                    alignment: Alignment.center,
                    child: Material(
                      borderRadius: BorderRadius.circular(8),
                      child: ArDriveStandardModalNew(
                        title: appLocalizationsOf(context).syncCancelled,
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              appLocalizationsOf(context).syncProgressSaved,
                              style: typography.paragraphNormal(),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .colors
                                    .themeWarningSubtle,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: ArDriveTheme.of(context)
                                      .themeData
                                      .colors
                                      .themeWarningEmphasis,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    size: 16,
                                    color: ArDriveTheme.of(context)
                                        .themeData
                                        .colors
                                        .themeWarningEmphasis,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      appLocalizationsOf(context)
                                          .syncCancelledDetails(
                                        syncState.drivesCompleted,
                                        syncState.totalDrives,
                                      ),
                                      style: typography.paragraphSmall(
                                        color: ArDriveTheme.of(context)
                                            .themeData
                                            .colors
                                            .themeWarningEmphasis,
                                        fontWeight: ArFontWeight.semiBold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          ModalAction(
                            action: () {
                              context.read<SyncCubit>().clearCancelledState();
                            },
                            title: appLocalizationsOf(context).ok,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (syncState is SyncCompleteWithErrors) {
                  return Align(
                    alignment: Alignment.center,
                    child: Material(
                      borderRadius: BorderRadius.circular(8),
                      child: ArDriveStandardModalNew(
                        title:
                            appLocalizationsOf(context).syncCompleteWithErrors,
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              appLocalizationsOf(context)
                                  .syncPartialSuccessMessage(
                                syncState.failedDrives,
                                syncState.totalDrives,
                              ),
                              style: typography.paragraphNormal(),
                            ),
                            if (syncState.errorMessages.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: ArDriveTheme.of(context)
                                      .themeData
                                      .colors
                                      .themeBgSubtle,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: ArDriveTheme.of(context)
                                        .themeData
                                        .colors
                                        .themeErrorDefault,
                                    width: 1,
                                  ),
                                ),
                                constraints: const BoxConstraints(
                                  maxHeight: 200,
                                ),
                                child: SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: syncState.errorMessages.entries
                                        .map((entry) => Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 4),
                                              child: Text(
                                                '• ${entry.value}',
                                                style:
                                                    typography.paragraphSmall(),
                                              ),
                                            ))
                                        .toList(),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        actions: [
                          ModalAction(
                            action: () {
                              context.read<SyncCubit>().clearErrorState();
                            },
                            title: appLocalizationsOf(context).close,
                          ),
                          ModalAction(
                            action: () {
                              final failedIds = syncState.failedDriveIds;
                              context.read<SyncCubit>().clearErrorState();
                              context
                                  .read<SyncCubit>()
                                  .retryFailedDrives(failedIds);
                            },
                            title:
                                appLocalizationsOf(context).retryFailedDrives,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Align(
                  alignment: Alignment.center,
                  child: Material(
                    borderRadius: BorderRadius.circular(8),
                    child: ProgressDialog(
                      useNewArDriveUI: true,
                      progressBar: ProgressBar(
                        percentage: context
                            .read<SyncCubit>()
                            .syncProgressController
                            .stream,
                      ),
                      percentageDetails: _syncStreamBuilder(
                        context,
                        builderWithData: (syncProgress) => Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (syncProgress.statusMessage != null)
                              Text(
                                syncProgress.statusMessage!,
                                style: typography.paragraphNormal(
                                  fontWeight: ArFontWeight.semiBold,
                                ),
                              )
                            else
                              Text(
                                appLocalizationsOf(context)
                                    .syncProgressPercentage(
                                  (syncProgress.progress * 100)
                                      .round()
                                      .toString(),
                                ),
                                style: typography.paragraphNormal(
                                  fontWeight: ArFontWeight.bold,
                                ),
                              ),
                            // Elapsed time — only shown
                            // after 5s to avoid clutter
                            // on fast syncs
                            StreamBuilder<int>(
                              stream: Stream.periodic(
                                const Duration(seconds: 1),
                                (i) => i,
                              ),
                              builder: (context, _) {
                                final elapsed = DateTime.now().difference(
                                    context.read<SyncCubit>().syncStartTime);
                                if (elapsed.inSeconds < 5) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    appLocalizationsOf(context).syncElapsedTime(
                                      elapsed.inSeconds.toString(),
                                    ),
                                    style: typography.paragraphSmall(
                                      color: ArDriveTheme.of(context)
                                          .themeData
                                          .colorTokens
                                          .textMid,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      progressDescription: _syncStreamBuilder(
                        context,
                        builderWithData: (syncProgress) => Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _getSyncProgressDescription(
                                context,
                                syncProgress,
                              ),
                              style: typography.paragraphNormal(
                                fontWeight: ArFontWeight.bold,
                              ),
                            ),
                            // ArConnect tab warning removed — unnecessary UX friction
                            if (syncProgress.hasErrors) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: ArDriveTheme.of(context)
                                      .themeData
                                      .colors
                                      .themeWarningSubtle,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.warning_amber_rounded,
                                      size: 16,
                                      color: ArDriveTheme.of(context)
                                          .themeData
                                          .colors
                                          .themeWarningEmphasis,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      appLocalizationsOf(context)
                                          .syncErrorsDetected(
                                              syncProgress.failedQueries),
                                      style: typography.paragraphSmall(
                                        color: ArDriveTheme.of(context)
                                            .themeData
                                            .colors
                                            .themeWarningEmphasis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      titleWidget: _syncStreamBuilder(
                        context,
                        builderWithData: (syncProgress) => Text(
                          _getSyncTitle(
                            context,
                            syncProgress,
                            isCurrentProfileArConnect,
                          ),
                          style: typography.heading5(
                            fontWeight: ArFontWeight.bold,
                          ),
                        ),
                      ),
                      actions: [
                        ModalAction(
                          action: () {
                            context.read<SyncCubit>().cancelSync();
                          },
                          title: appLocalizationsOf(context).cancelEmphasized,
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
        if (context.read<ConfigService>().flavor != Flavor.production)
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

  Widget _syncStreamBuilder(
    BuildContext context, {
    required Widget Function(SyncProgress s) builderWithData,
  }) =>
      StreamBuilder<SyncProgress>(
        stream: context.read<SyncCubit>().syncProgressController.stream,
        // Use current sync progress as initial data to prevent empty state flash
        initialData: context.read<SyncCubit>().syncProgress,
        builder: (context, snapshot) =>
            snapshot.hasData ? builderWithData(snapshot.data!) : Container(),
      );

  /// Returns the appropriate title for the sync modal based on sync type.
  /// ArConnect warning is handled separately in the modal content.
  String _getSyncTitle(
    BuildContext context,
    SyncProgress syncProgress,
    bool isArConnect,
  ) {
    // Always show sync-specific title regardless of ArConnect status
    if (syncProgress.isSingleDriveSync) {
      return appLocalizationsOf(context).syncingSingleDrive;
    } else {
      return appLocalizationsOf(context).syncingAllDrives;
    }
  }

  /// Returns the appropriate progress description for the sync modal.
  String _getSyncProgressDescription(
    BuildContext context,
    SyncProgress syncProgress,
  ) {
    if (syncProgress.isSingleDriveSync) {
      // Single drive sync - show drive name if available, otherwise fallback
      if (syncProgress.driveName != null) {
        return appLocalizationsOf(context).syncingDriveWithName(
          syncProgress.driveName!,
        );
      } else {
        return appLocalizationsOf(context).syncingOnlyOneDrive;
      }
    } else if (syncProgress.drivesCount > 1) {
      // Multiple drives - show "X of Y Drives Synced"
      return appLocalizationsOf(context).driveSyncedOfDrivesCount(
        syncProgress.drivesSynced,
        syncProgress.drivesCount,
      );
    } else if (syncProgress.drivesCount == 1) {
      // Single drive in all-drives sync
      return appLocalizationsOf(context).syncingOnlyOneDrive;
    } else {
      // drivesCount == 0, initial state
      return '';
    }
  }
}

/// The last thing a sync the user asked for shows: what it found, and then
/// nothing.
///
/// It reuses the modal the sync was already in so the wait ends where it
/// happened, but drops the scrim: there is no question to answer here, so the
/// app is usable underneath from the moment the result appears, and the
/// summary takes itself away after [syncSummaryDuration].
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

/// The dimming layer under a sync modal. Only a sync that blocks the app draws
/// one - see [SyncOverlay].
class SyncScrim extends StatelessWidget {
  const SyncScrim({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Container(
        color: Colors.black.withOpacity(0.5),
      ),
    );
  }
}
