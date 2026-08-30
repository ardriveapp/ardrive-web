import 'dart:async';

import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/components/progress_bar.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/sync/presentation/sync_elapsed_time.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

/// How wide the wait is allowed to get. Past this the phase line and the bar
/// drift apart on a wide monitor and stop reading as one thing.
const double _syncingContentMaxWidth = 420;

/// What the explorer draws while it is waiting to show a folder -
/// `DriveDetailLoadInProgress`.
///
/// This slot used to be a bare [CircularProgressIndicator]: no words, no
/// progress, no drive name, no time bound. That was survivable while a sync
/// held a scrim over the whole app, because nobody could reach this screen
/// during one. Now that a background sync leaves the app usable, and now that
/// opening a folder says it heard the click *before* it waits for the sync, a
/// drive clicked mid-sync lands here for the length of that sync - minutes, on
/// a large wallet - on a featureless spinner. A silent failure traded for a
/// blank wait.
///
/// So the explorer reports the sync, since the explorer is where the user is
/// looking: what is running, which drive they are waiting for, the phase the
/// sync names for itself, the same bar the modal fills, and a count of seconds
/// so a long wait reads as working rather than hung. Nothing here scrims, takes
/// focus or blocks navigation - it is one panel in a page the user can still
/// leave.
///
/// It is deliberately quieter than [DriveDetailUnsyncedCard], which occupies
/// the same slot for a drive that has *not* been synced: that one is a decision
/// the user has to make and is drawn as one, with headline type and two action
/// cards. This is a wait, and asks for nothing.
///
/// It has a second job, in the same frame: the drive list could not be read at
/// all - `DriveDetailDrivesUnavailable`. That is the third thing an empty
/// local database can mean, and until now the app rendered it as the second
/// ("Getting Started", two create-a-drive buttons). It belongs here rather
/// than in a screen of its own because it is the same sentence at the end of
/// the same wait, in the same panel, and it must not offer to create a drive
/// or claim the user has none.
class DriveDetailSyncingCard extends StatefulWidget {
  const DriveDetailSyncingCard({super.key}) : driveListUnavailable = false;

  /// The drive list could not be loaded: no progress, no phase, no elapsed
  /// time - nothing is running - just what happened and a way to try again.
  const DriveDetailSyncingCard.driveListUnavailable({super.key})
      : driveListUnavailable = true;

  /// Which of the panel's two jobs this is.
  final bool driveListUnavailable;

  @override
  State<DriveDetailSyncingCard> createState() => _DriveDetailSyncingCardState();
}

class _DriveDetailSyncingCardState extends State<DriveDetailSyncingCard> {
  /// The cubit's own broadcast stream of progress, read but never driven -
  /// this panel adds no request of any kind.
  ///
  /// Held in a field rather than read in `build`: [StreamBuilder] resubscribes
  /// and falls back to its initial data whenever the stream identity changes,
  /// so a stream fetched per build would reset the bar to where it was when
  /// this panel mounted every time a progress event arrived.
  late final Stream<SyncProgress> _progress;

  /// Where the bar starts.
  ///
  /// This panel mounts *during* a sync - that is the case it exists for - and
  /// the cubit replays nothing, so without a seed the bar would read empty
  /// until the next progress event, which in the unmeasurable phase can be
  /// half a minute away. A wait that is not a sync has no number to start
  /// from and gets a bar that says so.
  ///
  /// Decided once, here, because that is exactly when [StreamBuilder] reads
  /// it. Deciding it per build would mean handing the bar a different stream
  /// depending on the sync state, and a bar whose stream identity changes
  /// resubscribes and keeps whatever it was last showing - the seed would
  /// never be applied at all.
  late final LinearProgress _initialProgress;

  /// What the sync was reporting when this panel appeared, or null when no
  /// sync was running to report anything.
  late final SyncProgress? _progressAtMount;

  @override
  void initState() {
    super.initState();

    final syncCubit = context.read<SyncCubit>();
    _progress = syncCubit.syncProgressController.stream;
    _progressAtMount =
        _reportsProgress(syncCubit.state) ? syncCubit.syncProgress : null;
    _initialProgress = _progressAtMount ?? _indeterminate;
  }

  /// Whether this screen is waiting on a sync at all.
  static bool _isSyncing(SyncState state) =>
      state is SyncInProgress || state is SyncLoadingDrives;

  /// Whether there is an elapsed time worth showing.
  ///
  /// Only [SyncInProgress] sets a start time. `syncMetadataOnly` never does,
  /// so counting during [SyncLoadingDrives] counts from whenever the cubit was
  /// built - which reads "420s elapsed" under "Loading your drives...". The
  /// top bar withholds it in exactly this state for the same reason.
  static bool _hasElapsedWorthShowing(SyncState state) =>
      state is SyncInProgress;

  /// Whether the sync is far enough along to have progress to publish.
  /// Collecting drive metadata reports none at all - the top bar's ring has
  /// nothing to fill during it either - so this panel does not invent a nought
  /// to put on screen.
  static bool _reportsProgress(SyncState state) => state is SyncInProgress;

  @override
  Widget build(BuildContext context) {
    if (widget.driveListUnavailable) {
      return _frame(context, _unavailableContent(context));
    }

    return BlocBuilder<SyncCubit, SyncState>(
      builder: (context, syncState) {
        final isSyncing = _isSyncing(syncState);
        final reportsProgress = _reportsProgress(syncState);

        return StreamBuilder<SyncProgress>(
          stream: _progress,
          initialData: _progressAtMount,
          builder: (context, snapshot) {
            return BlocBuilder<DrivesCubit, DrivesState>(
              builder: (context, drivesState) {
                final content = _content(
                  context,
                  isSyncing: isSyncing,
                  showElapsed: _hasElapsedWorthShowing(syncState),
                  isLoadingDrives: syncState is SyncLoadingDrives,
                  progress: reportsProgress ? snapshot.data : null,
                  driveName: _driveName(drivesState, snapshot.data),
                );

                return _frame(context, content);
              },
            );
          },
        );
      },
    );
  }

  /// The shape every state of this panel is drawn in.
  ///
  /// The card the explorer's other full-panel states use on a wide screen, so
  /// the frame does not change shape when this becomes a folder listing, an
  /// unsynced drive, or the report that the drive list could not be read.
  Widget _frame(BuildContext context, Widget content) {
    return ScreenTypeLayout.builder(
      mobile: (context) => content,
      desktop: (context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.8,
          child: ArDriveCard(
            width: double.infinity,
            backgroundColor:
                ArDriveTheme.of(context).themeData.colorTokens.containerL1,
            content: content,
          ),
        ),
      ),
    );
  }

  /// The centred, width-capped, scrollable column both states lay themselves
  /// out in, so a 320px phone and a large text scale scroll rather than
  /// overflow.
  Widget _panel(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: _syncingContentMaxWidth,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: children,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// What the panel says when the drive list could not be read.
  ///
  /// Three things it deliberately does not do: claim the user has no drives,
  /// offer to create one, and show a bar. Nothing is running, so there is
  /// nothing to fill.
  Widget _unavailableContent(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return _panel([
      Text(
        appLocalizationsOf(context).driveListUnavailable,
        style: typography.heading4(fontWeight: ArFontWeight.bold),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      Text(
        appLocalizationsOf(context).driveListUnavailableDescription,
        style: typography.paragraphLarge(
          color: colorTokens.textLow,
          fontWeight: ArFontWeight.semiBold,
        ),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      ArDriveButtonNew(
        text: appLocalizationsOf(context).tryAgain,
        typography: typography,
        variant: ButtonVariant.primary,
        onPressed: () => context.read<DriveDetailCubit>().retryLoadingDrives(),
      ),
    ]);
  }

  /// The drive the user is waiting for, when anything on screen already knows
  /// it. The drive they selected is the one that will open, so it wins; a
  /// single-drive sync names its own drive and stands in when there is no
  /// selection to read yet.
  String? _driveName(DrivesState drivesState, SyncProgress? progress) {
    if (drivesState is DrivesLoadSuccess) {
      final selectedDriveId = drivesState.selectedDriveId;

      if (selectedDriveId != null) {
        for (final drive in [
          ...drivesState.userDrives,
          ...drivesState.sharedDrives,
        ]) {
          if (drive.id == selectedDriveId) {
            return drive.name;
          }
        }
      }
    }

    if (progress != null && progress.isSingleDriveSync) {
      return progress.driveName;
    }

    return null;
  }

  Widget _content(
    BuildContext context, {
    required bool isSyncing,
    required bool showElapsed,
    required bool isLoadingDrives,
    required SyncProgress? progress,
    required String? driveName,
  }) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    final String title;
    final String? subtitle;

    if (isSyncing) {
      // The same words the top bar uses for the same moment: the two report
      // one sync between them and must never name it differently.
      title = isLoadingDrives
          ? appLocalizationsOf(context).loadingYourDrives
          : progress != null && progress.isSingleDriveSync
              ? appLocalizationsOf(context).syncingSingleDrive
              : appLocalizationsOf(context).syncingAllDrives;
      // Says what the wait is for as well as what it is: this folder opens on
      // its own when the sync is done, and nothing has to be clicked again.
      subtitle = driveName == null
          ? null
          : appLocalizationsOf(context)
              .driveWillOpenWhenSyncFinishes(driveName);
    } else {
      title = driveName == null
          ? appLocalizationsOf(context).openingDrive
          : appLocalizationsOf(context).openingDriveNamed(driveName);
      subtitle = null;
    }

    // The phase names itself whenever the sync has one to give. Otherwise the
    // count of what has been found stands in - it needs no total, so it is
    // honest from the first batch, and it can only rise. The percentage is the
    // last resort, and only while it means something: an unmeasurable phase
    // must never leave a figure sitting still on screen, which is the one
    // thing this panel exists to stop.
    final String? detail;
    if (progress == null) {
      detail = null;
    } else if (progress.statusMessage != null) {
      detail = progress.statusMessage;
    } else if (progress.entitiesSynced > 0) {
      detail = appLocalizationsOf(context).syncFoundSoFar(
        progress.entitiesSynced,
      );
    } else if (progress.isIndeterminate) {
      detail = null;
    } else {
      detail = appLocalizationsOf(context).syncProgressPercentage(
        (progress.progress * 100).round().toString(),
      );
    }

    return _panel([
      Text(
        title,
        style: typography.heading4(
          fontWeight: ArFontWeight.bold,
        ),
        textAlign: TextAlign.center,
      ),
      if (subtitle != null) ...[
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: typography.paragraphLarge(
            color: colorTokens.textLow,
            fontWeight: ArFontWeight.semiBold,
          ),
          textAlign: TextAlign.center,
        ),
      ],
      const SizedBox(height: 24),
      // The modal's bar, not a second one: it already knows not to claim a
      // number during a phase that cannot measure itself, and not to rewind
      // when one ends.
      ProgressBar(
        // Keyed so the Column matches it by identity, not by position. When
        // the sync ends, subtitle, detail and the elapsed line all disappear
        // at once and the children list shrinks; an unkeyed bar would be
        // matched against a different widget, destroyed, and remounted at its
        // mount-time seed - a bar animating backwards from 99%, which is the
        // exact thing the sink beneath it exists to prevent.
        key: const ValueKey('driveDetailSyncProgress'),
        percentage: _progress,
        initialPercentage: _initialProgress,
      ),
      if (detail != null) ...[
        const SizedBox(height: 12),
        Text(
          detail,
          style: typography.paragraphNormal(
            color: colorTokens.textMid,
          ),
          textAlign: TextAlign.center,
        ),
      ],
      if (showElapsed) ...[
        const SizedBox(height: 4),
        const SyncElapsedTime(),
      ],
    ]);
  }
}

/// A bar with nothing to report: it moves, and claims nothing. What a wait on
/// the local database gets, since it is over in well under a second and has no
/// progress to publish.
final LinearProgress _indeterminate = _IndeterminateProgress();

class _IndeterminateProgress extends LinearProgress {
  @override
  double get progress => 0;

  @override
  bool get isIndeterminate => true;
}
