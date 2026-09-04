import 'dart:async';

import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/blocs/hide/global_hide_bloc.dart';
import 'package:ardrive/components/profile_card.dart';
import 'package:ardrive/components/topbar/help_button.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/search/search_modal.dart';
import 'package:ardrive/search/search_text_field.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/sync/presentation/sync_summary.dart';
import 'package:ardrive/user/name/presentation/bloc/profile_name_bloc.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_custom_event_properties.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AppTopBar extends StatelessWidget {
  const AppTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController();

    return SizedBox(
      height: 110,
      width: double.maxFinite,
      child: Padding(
        padding: const EdgeInsets.only(right: 17.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: SearchTextField(
                  controller: controller,
                  onFieldSubmitted: (query) {
                    showSearchModalDesktop(
                      context: context,
                      driveDetailCubit: context.read<DriveDetailCubit>(),
                      controller: controller,
                      drivesCubit: context.read<DrivesCubit>(),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 24),
            const Spacer(),
            const GlobalHideToggleButton(),
            const SizedBox(width: 8),
            const SyncButton(),
            const SizedBox(width: 8),
            const HelpButtonTopBar(),
            const SizedBox(width: 24),
            const ProfileCard(),
          ],
        ),
      ),
    );
  }
}

class GlobalHideToggleButton extends StatelessWidget {
  const GlobalHideToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GlobalHideBloc, GlobalHideState>(
      builder: (context, hideState) {
        if (!hideState.userHasHiddenDrive) {
          return const SizedBox.shrink();
        }

        final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

        final tooltip = hideState is ShowingHiddenItems
            ? 'Hide hidden items'
            : 'Show hidden items';

        final icon = hideState is ShowingHiddenItems
            ? ArDriveIcons.eyeOpen(
                color: colorTokens.textMid,
              )
            : ArDriveIcons.eyeClosed(
                color: colorTokens.textMid,
              );

        return ArDriveIconButton(
          tooltip: tooltip,
          icon: icon,
          onPressed: () {
            context.read<GlobalHideBloc>().add(
                  hideState is ShowingHiddenItems
                      ? HideItems(
                          userHasHiddenItems: hideState.userHasHiddenDrive)
                      : ShowItems(
                          userHasHiddenItems: hideState.userHasHiddenDrive,
                        ),
                );
          },
        );
      },
    );
  }
}

/// The size [ArDriveIcon] renders at by default, and so the size of the slot
/// every state of [SyncButton] has to fit into for the top bar to hold still
/// when a sync starts or stops.
const double _syncIndicatorSize = 24;

/// The row height [ArDriveDropdown] assumes for every item: it sizes its
/// overlay as `items.length * height`, so an item that is taller than this has
/// to be paid for with an explicit `maxHeight`.
const double _dropdownRowHeight = 48;

/// The height the status header asks for, and the reason [_SyncButtonMenu]
/// hands the dropdown a `maxHeight` whenever it shows one. It is a minimum, not
/// a cap: a larger text scale grows the header and the menu scrolls, rather
/// than the header overflowing.
const double _syncStatusHeaderHeight = 96;

/// How wide the status header lets the menu grow. The dropdown wraps its items
/// in an [IntrinsicWidth], so this is what sets the open menu's width while a
/// sync runs.
const double _syncStatusHeaderWidth = 260;

/// What the sync indicator has to say, in the words the sync modal uses for the
/// same thing.
class _SyncStatus {
  const _SyncStatus({
    required this.title,
    this.detail,
    this.showElapsed = false,
    this.isError = false,
    this.detailMaxLines = 1,
  });

  /// What is being synced - the modal's own title - or, for a sync that
  /// failed, that it did.
  final String title;

  /// The phase the sync names for itself, the percentage when it names none,
  /// or how many drives a failed sync could not read.
  final String? detail;

  /// Whether the sync has a start time worth counting from.
  final bool showElapsed;

  /// Whether this is a sync that failed rather than one that is running, so
  /// the header reads as a problem instead of as progress.
  final bool isError;

  /// How much room [detail] gets. A running sync's phase is one short line; a
  /// failure counts drives, which wraps on a phone.
  final int detailMaxLines;

  /// The same two lines, for a pointer that has somewhere to hover.
  String get asTooltip => detail == null ? title : '$title\n$detail';
}

/// What the top bar has to say about a sync that just ended, and for how long.
class SyncAnnouncement {
  const SyncAnnouncement({
    required this.identity,
    required this.showFor,
    this.lead,
    this.trailing,
    this.isError = false,
  });

  /// Which announcement this is. A new identity restarts the few seconds it
  /// gets; the same one arriving again because something rebuilt does not, so
  /// a result cannot be stretched by a resize - and two syncs that read
  /// identically are still two results, because their identities differ.
  final Object identity;

  /// How long it stays, counted from when the sync ended rather than from when
  /// this was built - see [syncSummaryRemaining].
  final Duration showFor;

  /// The line that may be shortened when there is not room for everything.
  final String? lead;

  /// The line that may not: what a sync could not read is the whole reason for
  /// saying anything, so it never gets ellipsized in favour of a drive name.
  final String? trailing;

  /// Whether this is a failure. It is drawn as one - a report nobody asked for
  /// must not be mistaken for a clean result.
  final bool isError;
}

/// The top bar's sync control: the resync menu, and - while a sync is running,
/// or after one that failed - the only place a background sync reports itself.
///
/// A sync the user asked for still gets the modal over the whole app. One that
/// merely happened gets this: a ring that turns, and the phase, percentage and
/// elapsed time inside the menu the ring already opens - a tap, not a hover, so
/// the phone gets them too. A failure it reports here as well, rather than
/// dropping a scrim over whatever the user had moved on to.
class SyncButton extends StatelessWidget {
  const SyncButton({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SyncCubit, SyncState>(
      builder: (context, syncState) {
        final syncCubit = context.read<SyncCubit>();

        // One shape for every state, and that is the point. This slot used to
        // hold three structurally different subtrees - the menu on its own
        // when idle, a StreamBuilder above it while a sync ran, a flash above
        // that just after one finished - so every transition changed the
        // widget type at this position and took [ArDriveDropdown]'s element,
        // and its open/closed flag, down with it. An open menu vanished the
        // instant a sync started or ended, and a thumb already moving towards
        // Resync landed on the page behind.
        //
        // The stream is subscribed to in every state rather than only while a
        // sync runs. It is a broadcast controller the cubit already owns, so
        // listening costs nothing and asks nobody for anything.
        return StreamBuilder<SyncProgress>(
          stream: syncCubit.syncProgressController.stream,
          // The controller replays nothing, so a button mounted mid-sync would
          // show an empty ring until the next event without this.
          initialData: syncCubit.syncProgress,
          builder: (context, snapshot) => _build(
            context,
            syncState,
            snapshot.data,
          ),
        );
      },
    );
  }

  Widget _build(
    BuildContext context,
    SyncState syncState,
    SyncProgress? syncProgress,
  ) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    // Only a sync nobody asked for reports its failure here. One the user
    // asked for is holding a modal that says all of this already, with the
    // same retry - see [SyncOverlay].
    final errors = syncState is SyncCompleteWithErrors &&
            syncState.trigger != SyncTrigger.userInitiated
        ? syncState
        : null;

    final isSyncing = syncState is SyncInProgress;

    final _SyncStatus? status;
    final Widget indicator;

    if (syncState is SyncLoadingDrives) {
      // Loading drive metadata reports no progress at all, so the ring has
      // nothing to fill and just turns.
      status = _SyncStatus(
        title: appLocalizationsOf(context).loadingYourDrives,
      );
      indicator = const _SyncProgressRing();
    } else if (isSyncing) {
      status = _syncStatus(context, syncProgress);
      // A phase that cannot measure itself hands the ring no value, so it
      // sweeps as well as turns - the same honesty the modal's bar gets. The
      // rotation is its own repeating animation either way, so the ring never
      // freezes into a static arc.
      indicator = _SyncProgressRing(
        progress: syncProgress != null && syncProgress.isIndeterminate
            ? null
            : syncProgress?.progress,
      );
    } else if (errors != null) {
      status = _SyncStatus(
        title: appLocalizationsOf(context).syncCompleteWithErrors,
        detail: appLocalizationsOf(context).syncDrivesFailed(
          errors.failedDrives,
          errors.totalDrives,
        ),
        isError: true,
        detailMaxLines: 2,
      );
      indicator = ArDriveIcons.triangle(color: colorTokens.strokeRed);
    } else {
      status = null;
      indicator = ArDriveIcons.refresh(color: colorTokens.textMid);
    }

    return SyncSummaryFlash(
      announcement: _announcement(context, syncState, errors),
      child: _SyncButtonMenu(
        status: status,
        isSyncing: isSyncing,
        failedDriveIds: errors?.failedDriveIds,
        child: indicator,
      ),
    );
  }

  /// What the button has to announce right now, or null when it has nothing.
  SyncAnnouncement? _announcement(
    BuildContext context,
    SyncState syncState,
    SyncCompleteWithErrors? errors,
  ) {
    if (errors != null) {
      // Gated the same way a result is: SyncCompleteWithErrors stays the
      // cubit's state until the next sync, so without this the red pill
      // replayed in full every time the top bar was rebuilt - on every drive
      // click, for the rest of the session.
      final remaining = syncSummaryRemainingSince(errors.completedAt);
      if (remaining == Duration.zero) {
        return null;
      }

      return SyncAnnouncement(
        // The state itself. Two failures that read identically are equal, so
        // bloc would never deliver the second one anyway - and a failure that
        // has been cleared and happened again is a different object.
        identity: errors,
        showFor: remaining,
        lead: appLocalizationsOf(context).syncCompleteWithErrors,
        trailing: appLocalizationsOf(context).syncDrivesFailed(
          errors.failedDrives,
          errors.totalDrives,
        ),
        isError: true,
      );
    }

    if (syncState is SyncComplete &&
        syncState.trigger != SyncTrigger.userInitiated &&
        // A result that has already had its few seconds is not announced again
        // because the bar was rebuilt - see [syncSummaryIsFresh].
        syncSummaryIsFresh(syncState)) {
      final summary = syncCompleteSummaryParts(
        appLocalizationsOf(context),
        syncState,
      );

      return SyncAnnouncement(
        // Which result this is, not what it says: two zero-change syncs read
        // identically, and the second one still has to show.
        identity: syncState.sequence,
        showFor: syncSummaryRemaining(syncState),
        lead: summary.arrived,
        trailing: summary.unreadable,
      );
    }

    return null;
  }

  /// Two lines: what sync is doing, and how far along it is. The phase names
  /// itself when the sync has one to give; the percentage stands in when it
  /// doesn't - the same pairing, and the same title, as the sync modal.
  _SyncStatus _syncStatus(BuildContext context, SyncProgress? syncProgress) {
    if (syncProgress == null) {
      return _SyncStatus(
        title: appLocalizationsOf(context).syncingAllDrives,
        showElapsed: true,
      );
    }

    return _SyncStatus(
      title: syncProgress.isSingleDriveSync
          ? appLocalizationsOf(context).syncingSingleDrive
          : appLocalizationsOf(context).syncingAllDrives,
      // The percentage stands in only when the sync has no phase to name and
      // a number worth showing; an unmeasurable phase always has a message.
      detail: syncProgress.statusMessage ??
          (syncProgress.isIndeterminate
              ? null
              : appLocalizationsOf(context).syncProgressPercentage(
                  (syncProgress.progress * 100).round().toString(),
                )),
      showElapsed: true,
    );
  }
}

/// What a finished background sync found - or could not - beside the indicator
/// that was turning for it, for [syncSummaryDuration] and no longer.
///
/// It hangs off the button in an overlay rather than in the top bar's own row:
/// a result that arrives while the user is reading something else must not
/// push the bar's contents sideways, and it has to be able to leave again
/// without moving them back.
///
/// It is mounted in every state, with nothing to say in most of them, so that
/// the button's subtree does not change shape when a sync ends - see
/// [SyncButton].
class SyncSummaryFlash extends StatefulWidget {
  const SyncSummaryFlash({
    super.key,
    required this.announcement,
    required this.child,
  });

  /// What there is to say, or null when there is nothing.
  final SyncAnnouncement? announcement;

  /// The sync button the announcement is anchored to.
  final Widget child;

  @override
  State<SyncSummaryFlash> createState() => _SyncSummaryFlashState();
}

class _SyncSummaryFlashState extends State<SyncSummaryFlash> {
  Timer? _dismiss;

  /// The identity of the announcement that has already had its turn. Kept
  /// after it is hidden: without it, the next rebuild would find the same
  /// announcement still on the cubit's state and start it over.
  Object? _announced;

  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _announce();
  }

  @override
  void didUpdateWidget(covariant SyncSummaryFlash oldWidget) {
    super.didUpdateWidget(oldWidget);
    // No setState: a build follows this immediately.
    _announce();
  }

  void _announce() {
    final announcement = widget.announcement;

    if (announcement == null) {
      _dismiss?.cancel();
      _dismiss = null;
      _announced = null;
      _visible = false;
      return;
    }

    if (announcement.identity == _announced) {
      return;
    }

    _announced = announcement.identity;
    _visible = true;
    _dismiss?.cancel();
    _dismiss = Timer(announcement.showFor, () {
      if (mounted) {
        setState(() => _visible = false);
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
    final announcement = widget.announcement;

    return ArDriveOverlay(
      visible: _visible && announcement != null,
      // No barrier: a report is not a question, so it never takes the next
      // click - the resync menu underneath still opens on the first one.
      closeOnBarrierTap: false,
      anchor: const Aligned(
        follower: Alignment.topRight,
        target: Alignment.bottomRight,
        offset: Offset(0, 8),
        // The button sits at the top bar's trailing edge, so on a phone the
        // summary is wider than the room left of it.
        shiftToWithinBound: AxisFlag(x: true),
      ),
      content: announcement == null
          ? const SizedBox.shrink()
          : _SyncSummaryPill(announcement: announcement),
      child: widget.child,
    );
  }
}

/// The announcement itself: a quiet couple of lines in the surface colours, so
/// a result that needs nothing from the user does not read like a warning - and
/// in the red tokens when it is one, so a failure is never mistaken for a
/// clean result.
///
/// The pill is capped at [_syncStatusHeaderWidth], which on a phone is most of
/// the screen, so [SyncAnnouncement.lead] is allowed two lines and then an
/// ellipsis. [SyncAnnouncement.trailing] is not: it goes on its own line
/// underneath, full length. On one line it was joined last, so a long drive
/// name pushed it past the cap and the ellipsis ate exactly the clause that
/// says this sync has holes in it.
class _SyncSummaryPill extends StatelessWidget {
  const _SyncSummaryPill({required this.announcement});

  final SyncAnnouncement announcement;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final lead = announcement.lead;
    final trailing = announcement.trailing;
    final textColor =
        announcement.isError ? colorTokens.textRed : colorTokens.textHigh;

    return IgnorePointer(
      // The margin is what keeps a gutter on the narrowest phone: the anchor's
      // shiftToWithinBound pulls the follower to x=0, so without it the pill
      // sits flush against the screen edge while its right side keeps its
      // inset, and reads as misaligned rather than as a floating card.
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        constraints: const BoxConstraints(maxWidth: _syncStatusHeaderWidth),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colorTokens.containerL1,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: announcement.isError
                ? colorTokens.strokeRed
                : colorTokens.strokeLow,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (lead != null)
              Text(
                lead,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: typography.paragraphSmall(color: textColor),
              ),
            if (trailing != null)
              Text(
                trailing,
                style: typography.paragraphSmall(color: textColor),
              ),
          ],
        ),
      ),
    );
  }
}

/// The resync menu every state of [SyncButton] hangs off, so that a running
/// sync never costs the user the actions.
///
/// While a sync runs the menu also carries a [_SyncStatusHeader], because the
/// menu is the one surface a phone can reach: [SyncButton] is mounted in
/// `MobileAppBar` too, where nothing hovers and a tooltip is never seen. After
/// a background sync fails, the same header carries the failure and the menu
/// carries the retry.
class _SyncButtonMenu extends StatelessWidget {
  const _SyncButtonMenu({
    this.status,
    this.isSyncing = false,
    this.failedDriveIds,
    required this.child,
  });

  /// The running sync, the failure it ended in, or null when neither.
  final _SyncStatus? status;

  /// Whether a sync is running. `SyncCubit.startSync` turns a request away
  /// while one is - a guard written for a world where a running sync scrimmed
  /// the app, so nobody could ask. Now the menu is fully interactive, and an
  /// item that looks normal, closes the menu, records a Plausible event and
  /// drops the request is a lie. These say what they are instead.
  final bool isSyncing;

  /// The drives a background sync failed on, when it did: the retry has to
  /// outlive the few seconds the announcement gets.
  final List<String>? failedDriveIds;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final status = this.status;
    final failedDriveIds = this.failedDriveIds;
    final iconColor = ArDriveTheme.of(context).themeData.colors.themeFgDefault;

    final items = [
      ArDriveDropdownItem(
        // Nothing at all rather than a call that returns immediately: an event
        // must not be recorded for a sync that never starts.
        onClick: isSyncing
            ? null
            : () {
                context.read<SyncCubit>().startSync(deepSync: false);
                context.read<ProfileNameBloc>().add(RefreshProfileName());
                PlausibleEventTracker.trackResync(type: ResyncType.resync);
              },
        content: ArDriveDropdownItemTile(
          name: appLocalizationsOf(context).resync,
          isDisabled: isSyncing,
          icon: ArDriveIcons.refresh(color: iconColor),
        ),
      ),
      ArDriveDropdownItem(
        onClick: isSyncing
            ? null
            : () {
                context.read<SyncCubit>().startSync(deepSync: true);
                context.read<ProfileNameBloc>().add(RefreshProfileName());
                PlausibleEventTracker.trackResync(type: ResyncType.deepResync);
              },
        content: ArDriveDropdownItemTile(
          name: appLocalizationsOf(context).deepResync,
          isDisabled: isSyncing,
          icon: ArDriveIcons.cloudSync(color: iconColor),
        ),
      ),
      if (failedDriveIds != null && failedDriveIds.isNotEmpty)
        ArDriveDropdownItem(
          onClick: isSyncing
              ? null
              : () {
                  final syncCubit = context.read<SyncCubit>();
                  syncCubit.clearErrorState();
                  syncCubit.retryFailedDrives(failedDriveIds);
                },
          content: ArDriveDropdownItemTile(
            name: appLocalizationsOf(context).retryFailedDrives,
            isDisabled: isSyncing,
            icon: ArDriveIcons.cloudSync(color: iconColor),
          ),
        ),
    ];

    return HoverWidget(
      tooltip: status?.asTooltip ?? appLocalizationsOf(context).resyncTooltip,
      child: ArDriveDropdown(
        anchor: const Aligned(
          follower: Alignment.topRight,
          target: Alignment.bottomRight,
          // The menu hangs off the top bar's trailing edge, so on a narrow
          // phone it is wider than the room left of the button. Let the portal
          // pull it back rather than run the text off the left edge.
          shiftToWithinBound: AxisFlag(x: true),
        ),
        // The dropdown would otherwise size itself as `items.length * 48` and
        // cut the header off.
        maxHeight: status == null
            ? null
            : _syncStatusHeaderHeight + items.length * _dropdownRowHeight,
        // A header rather than an item: it is there to be read, so it must not
        // light up like an action or close the menu when a thumb lands on it.
        header: status == null ? null : _SyncStatusHeader(status: status),
        items: items,
        child: SizedBox(
          width: _syncIndicatorSize,
          height: _syncIndicatorSize,
          child: child,
        ),
      ),
    );
  }
}

/// The phase, the percentage and the elapsed time - or the failure - sitting
/// above the resync actions in the menu the sync indicator opens.
///
/// This is the mobile half of the indicator. The ring says a sync is running;
/// this says which one, how far it has got and how long it has been at it,
/// without a pointer.
class _SyncStatusHeader extends StatelessWidget {
  const _SyncStatusHeader({required this.status});

  final _SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final detail = status.detail;

    return Container(
      width: _syncStatusHeaderWidth,
      constraints: const BoxConstraints(minHeight: _syncStatusHeaderHeight),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colorTokens.strokeLow),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (status.isError) ...[
                ArDriveIcons.triangle(
                  size: 16,
                  color: colorTokens.strokeRed,
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  status.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: typography.paragraphNormal(
                    fontWeight: ArFontWeight.semiBold,
                    color: status.isError
                        ? colorTokens.textRed
                        : colorTokens.textHigh,
                  ),
                ),
              ),
            ],
          ),
          if (detail != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                detail,
                maxLines: status.detailMaxLines,
                overflow: TextOverflow.ellipsis,
                style: typography.paragraphSmall(
                  color: colorTokens.textMid,
                ),
              ),
            ),
          if (status.showElapsed)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: _SyncElapsedTime(),
            ),
        ],
      ),
    );
  }
}

/// Seconds since the running sync started, counted where a phone can read it.
class _SyncElapsedTime extends StatefulWidget {
  const _SyncElapsedTime();

  @override
  State<_SyncElapsedTime> createState() => _SyncElapsedTimeState();
}

class _SyncElapsedTimeState extends State<_SyncElapsedTime> {
  // Held in a field, not built in `build`: progress events rebuild this header
  // often, and a stream rebuilt each time restarts its timer before it fires,
  // so the counter would tick to the sync's cadence instead of the clock's.
  final Stream<int> _ticks =
      Stream.periodic(const Duration(seconds: 1), (i) => i);

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return StreamBuilder<int>(
      stream: _ticks,
      builder: (context, _) {
        final elapsed =
            DateTime.now().difference(context.read<SyncCubit>().syncStartTime);

        return Text(
          appLocalizationsOf(context).syncElapsedTime(
            elapsed.inSeconds.toString(),
          ),
          style: typography.paragraphSmall(color: colorTokens.textLow),
        );
      },
    );
  }
}

/// The key the ring's continuous rotation hangs off, so a test can prove the
/// indicator is still moving.
const Key syncIndicatorMotionKey = Key('syncIndicatorMotion');

/// A turning ring with the refresh glyph inside it, filling the slot the idle
/// icon leaves behind.
///
/// [progress] fills the ring once the sync reports any - but the ring turns
/// either way. Sync progress plateaus for long stretches, and an arc that has
/// not moved in a minute reads as a hang, so the arc keeps rotating whatever
/// its length is doing.
class _SyncProgressRing extends StatefulWidget {
  const _SyncProgressRing({this.progress});

  final double? progress;

  @override
  State<_SyncProgressRing> createState() => _SyncProgressRingState();
}

class _SyncProgressRingState extends State<_SyncProgressRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation;

  @override
  void initState() {
    super.initState();
    // Built here rather than lazily on first use, so dispose() never has to
    // create a ticker on a widget that is already coming down.
    _rotation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final progress = widget.progress;

    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox.expand(
          child: RotationTransition(
            key: syncIndicatorMotionKey,
            turns: _rotation,
            child: CircularProgressIndicator(
              value: progress != null && progress > 0 ? progress : null,
              strokeWidth: 2,
              backgroundColor: colorTokens.strokeHigh,
              valueColor: AlwaysStoppedAnimation<Color>(
                colorTokens.buttonPrimaryDefault,
              ),
            ),
          ),
        ),
        // The same token the idle icon uses, so the glyph does not change
        // colour the instant a sync starts.
        ArDriveIcons.refresh(
          size: _syncIndicatorSize / 2,
          color: colorTokens.textMid,
        ),
      ],
    );
  }
}
