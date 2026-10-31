import 'dart:math' as math;

import 'package:ardrive/drives_list/presentation/drives_list_cubit.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive/pages/drive_detail/components/item_menus.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/presentation/full_resync_confirmation.dart';
import 'package:ardrive/sync/presentation/sync_history_panel.dart';
import 'package:ardrive/user/name/presentation/bloc/profile_name_bloc.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_custom_event_properties.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Every drive-wide sync action, on the page about drives.
///
/// These lived behind the top bar's indicator, which was present on every
/// screen whether or not anything was happening. The indicator now appears only
/// when there is something to report, so the controls needed a home that is
/// always there - and the drives list is it: these all act on every drive, and
/// this is the page that lists them.
///
/// A split button: the main half does the one obvious thing for the page as
/// it stands, and the chevron opens every action. It is the page's only sync
/// control.
///
/// Always the outline variant, never red: the sidebar's New is the view's one
/// primary, and a red Sync beside it was two filled red buttons with
/// different jobs on one screen.
class DrivesSyncMenu extends StatelessWidget {
  const DrivesSyncMenu({super.key});

  /// The chevron half, the one that opens the menu.
  static const moreKey = Key('drivesSyncMenuMore');

  /// The main half, the one that acts.
  static const primaryKey = Key('drivesSyncMenuPrimary');

  @override
  Widget build(BuildContext context) {
    final iconColor = ArDriveTheme.of(context).themeData.colorTokens.textHigh;

    return BlocBuilder<SyncCubit, SyncState>(
      builder: (context, syncState) {
        final isSyncing = driveSyncUnavailable(syncState);
        final errors = syncState is SyncCompleteWithErrors ? syncState : null;

        // How many drives are ticked, so both actions can say which set they
        // will run over. Watched rather than read: ticking a drive has to
        // relabel these the moment it happens.
        //
        // Nullable because selection belongs to the drives list and this menu
        // does not: it needs SyncCubit to do its job and should not acquire a
        // second hard dependency for a label. Without one it behaves exactly
        // as it did before selection existed.
        final drivesList = context.watch<DrivesListCubit?>();
        final selection = drivesList?.selectionCount ?? 0;
        final listState = drivesList?.state;

        // The drives the network has moved on without. Each one says so in
        // its row; this is where they can be synced on their own.
        final changed = listState is DrivesListLoaded
            ? listState.drivesWithUnreadChanges.length
            : 0;
        final offersChanged = drivesList != null && changed > 0;

        // Stopping only while there is a run that stopping can stop:
        // `cancelSync` cancels the token a running sync holds, and the
        // drive-list refresh holds none. The drive's own syncing card makes
        // the same distinction.
        final canStop = syncState is SyncInProgress;

        final offersRetry = errors != null && errors.failedDriveIds.isNotEmpty;

        // The label style every button uses, so this reads as one of them.
        // One height for both halves, from the label's line at the reader's
        // text scale, so they stay one control when the text grows: the
        // regular button's 40 at a scale of 1.
        final labelStyle = ArDriveTypographyNew.of(context).paragraphLarge(
          fontWeight: ArFontWeight.semiBold,
        );
        final height = math.max(
          40.0,
          MediaQuery.textScalerOf(context).scale(labelStyle.fontSize ?? 16) *
                  (labelStyle.height ?? 1.5) +
              16,
        );

        // Named for what it does. With nothing ticked it syncs every drive,
        // so it says so, before the first sync and after it alike. With
        // drives ticked it syncs those; the title row says how many, so this
        // does not say it again. While the drive list refreshes it keeps its
        // label and is unavailable, so it neither changes width nor offers a
        // sync that would be refused.
        final syncLabel = selection > 0
            ? appLocalizationsOf(context).driveListSyncSelected
            : appLocalizationsOf(context).syncAllDrives;
        final String primaryLabel;
        final VoidCallback? onPrimary;
        if (canStop) {
          primaryLabel = appLocalizationsOf(context).syncStopRunning;
          onPrimary = () => context.read<SyncCubit>().cancelSync();
        } else {
          primaryLabel = syncLabel;
          onPrimary = isSyncing ? null : () => _sync(context, drivesList);
        }

        Widget buildMenu(Widget chevron) => ArDriveDropdown(
              // The two sync items carry a line saying what they do, so they are
              // taller than the rest, and the menu, which sizes itself from a
              // single item height, is told the total instead.
              maxHeight: ((offersRetry ? 3 : 2) * describedDropdownItemHeight +
                          (offersChanged ? 2 : 1) * 48) *
                      MediaQuery.textScalerOf(context)
                          .scale(1)
                          .clamp(1.0, 2.0) +
                  ArDriveDropdownItem.dividerHeight,
              anchor: const Aligned(
                follower: Alignment.topRight,
                target: Alignment.bottomRight,
                offset: Offset(0, 4),
                shiftToWithinBound: AxisFlag(x: true),
              ),
              items: [
                ArDriveDropdownItem(
                  // Nothing at all rather than a call that returns immediately: an
                  // event must not be recorded for a sync that never starts.
                  onClick: isSyncing ? null : () => _sync(context, drivesList),
                  content: ArDriveDropdownItemTile(
                    // One name for syncing everything, wherever it is offered, and
                    // whether or not anything has synced before.
                    name: syncLabel,
                    description:
                        appLocalizationsOf(context).syncMenuSyncDescription,
                    height: describedDropdownItemHeight,
                    icon: ArDriveIcons.refresh(color: iconColor),
                    isDisabled: isSyncing,
                  ),
                ),
                ArDriveDropdownItem(
                  onClick: isSyncing
                      ? null
                      : () async {
                          // Read before the confirmation: it is a dialog, and the
                          // menu's context is not this widget's to use after it.
                          final syncCubit = context.read<SyncCubit>();
                          final confirmed = await confirmFullResync(
                            context,
                            selection > 0
                                ? FullResyncScope.selected(selection)
                                : const FullResyncScope.allDrives(),
                          );
                          if (!confirmed) return;

                          if (drivesList != null) {
                            drivesList.syncSelectedDrives(deep: true);
                          } else {
                            syncCubit.startSync(deepSync: true);
                          }
                          PlausibleEventTracker.trackResync(
                              type: ResyncType.deepResync);
                        },
                  content: ArDriveDropdownItemTile(
                    name: selection > 0
                        ? appLocalizationsOf(context)
                            .driveListDeepResyncSelected
                        : appLocalizationsOf(context).deepResync,
                    description: appLocalizationsOf(context)
                        .syncMenuFullResyncDescription,
                    height: describedDropdownItemHeight,
                    icon: ArDriveIcons.cloudSync(color: iconColor),
                    isDisabled: isSyncing,
                  ),
                ),
                if (offersChanged)
                  ArDriveDropdownItem(
                    onClick: isSyncing
                        ? null
                        : () {
                            drivesList.syncDrivesWithUnreadChanges();
                            PlausibleEventTracker.trackResync(
                                type: ResyncType.resync);
                          },
                    content: ArDriveDropdownItemTile(
                      name: appLocalizationsOf(context)
                          .driveListSyncChanged(changed),
                      icon: ArDriveIcons.refresh(color: iconColor),
                      isDisabled: isSyncing,
                    ),
                  ),
                // A failed run, in the top bar's words: its count is of the
                // drives that run covered, and its retry is Try again.
                if (offersRetry)
                  ArDriveDropdownItem(
                    onClick: isSyncing
                        ? null
                        : () {
                            final cubit = context.read<SyncCubit>();
                            cubit.clearErrorState();
                            cubit.retryFailedDrives(errors.failedDriveIds);
                          },
                    content: ArDriveDropdownItemTile(
                      name: appLocalizationsOf(context).tryAgain,
                      description: appLocalizationsOf(context).syncDrivesFailed(
                          errors.failedDrives, errors.totalDrives),
                      height: describedDropdownItemHeight,
                      icon: ArDriveIcons.triangle(color: iconColor),
                      isDisabled: isSyncing,
                    ),
                  ),
                // The actions, then the record: a line between doing and
                // reading, as every other menu groups its items.
                const ArDriveDropdownItem.divider(),
                ArDriveDropdownItem(
                  onClick: () => showSyncHistoryModal(context),
                  content: ArDriveDropdownItemTile(
                    name: appLocalizationsOf(context).syncHistory,
                    // Not More info's glyph: this is a record of past syncs.
                    icon: ArDriveIcons.history(color: iconColor),
                  ),
                ),
              ],
              // Styled as a button, but not one: `ArDriveDropdown` opens on a tap
              // that reaches it, and a real button swallows that tap with its own
              // handler - so the menu never opened. Every other dropdown in the app
              // passes an inert child for the same reason.
              child: chevron,
            );

        return _SplitButton(
          height: height,
          onPrimary: onPrimary,
          primaryLabel: primaryLabel,
          moreLabel: appLocalizationsOf(context).moreSyncOptions,
          labelStyle: labelStyle,
          // The dropdown wraps the chevron, and only the chevron: the main
          // half acts on a tap, the chevron opens the menu on one.
          wrapChevron: (chevron) => buildMenu(chevron),
        );
      },
    );
  }

  /// Item one's action, and the main half's when it syncs.
  ///
  /// Acts on the ticked drives when there are any. A control that quietly
  /// ignored a selection the reader had just made would be the worst of both.
  static void _sync(BuildContext context, DrivesListCubit? drivesList) {
    if (drivesList != null) {
      drivesList.syncSelectedDrives(deep: false);
    } else {
      context.read<SyncCubit>().startSync(deepSync: false);
    }
    context.read<ProfileNameBloc>().add(RefreshProfileName());
    PlausibleEventTracker.trackResync(type: ResyncType.resync);
  }
}

/// The split button: one rounded outline around both halves, a hairline
/// between them, and the design system's own button tokens.
///
/// Drawn by hand for the chevron's sake: `ArDriveDropdown` opens on a tap that
/// reaches it, and a real button swallows that tap with its own handler, so the
/// chevron half is inert and only reads the pointer for its fill. The main half
/// handles its own tap.
///
/// The outline variant, with `ArDriveButtonNew`'s tokens: a disabled half is
/// filled `buttonDisabled` with its label in `textXLow`, as a disabled button
/// is. Colours are animated, so a change of state reads as one rather than as
/// a flicker.
class _SplitButton extends StatefulWidget {
  const _SplitButton({
    required this.height,
    required this.onPrimary,
    required this.primaryLabel,
    required this.moreLabel,
    required this.labelStyle,
    required this.wrapChevron,
  });

  final double height;
  final VoidCallback? onPrimary;
  final String primaryLabel;
  final String moreLabel;
  final TextStyle labelStyle;
  final Widget Function(Widget chevron) wrapChevron;

  @override
  State<_SplitButton> createState() => _SplitButtonState();
}

class _SplitButtonState extends State<_SplitButton> {
  static const _fade = Duration(milliseconds: 150);

  bool _primaryHovered = false;
  bool _primaryPressed = false;
  bool _moreHovered = false;
  bool _morePressed = false;

  Color _fill(
    ArDriveColorTokens tokens, {
    required bool enabled,
    required bool hovered,
    required bool pressed,
  }) {
    if (!enabled) return tokens.buttonDisabled;
    return pressed
        ? tokens.buttonOutlinePress
        : hovered
            ? tokens.buttonOutlineHover
            : tokens.buttonOutlineDefault;
  }

  /// One half's pointer handling. Reading the pointer takes nothing from the
  /// gesture the menu opens on.
  Widget _pointer({
    required bool enabled,
    required ValueChanged<bool> onHover,
    required ValueChanged<bool> onPress,
    required Widget child,
  }) =>
      MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => onHover(true),
        onExit: (_) {
          onHover(false);
          onPress(false);
        },
        child: Listener(
          onPointerDown: enabled ? (_) => onPress(true) : null,
          onPointerUp: (_) => onPress(false),
          onPointerCancel: (_) => onPress(false),
          child: child,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final tokens = ArDriveTheme.of(context).themeData.colorTokens;
    final primaryEnabled = widget.onPrimary != null;
    final active = (_primaryHovered && primaryEnabled) || _moreHovered;

    final outline = active ? tokens.strokeHigh : tokens.strokeMid;

    final primaryHalf = Semantics(
      button: true,
      enabled: primaryEnabled,
      label: widget.primaryLabel,
      onTap: widget.onPrimary,
      excludeSemantics: true,
      // Tab reaches it and Enter or Space syncs, as a click does.
      child: ArDriveFocusable(
        onActivate: primaryEnabled ? widget.onPrimary : null,
        child: GestureDetector(
          key: DrivesSyncMenu.primaryKey,
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPrimary,
          child: _pointer(
            enabled: primaryEnabled,
            onHover: (v) => setState(() => _primaryHovered = v),
            onPress: (v) {
              if (_primaryPressed != v) setState(() => _primaryPressed = v);
            },
            child: AnimatedContainer(
              duration: _fade,
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: _fill(
                  tokens,
                  enabled: primaryEnabled,
                  hovered: _primaryHovered,
                  pressed: _primaryPressed,
                ),
              ),
              // As wide as its label and no wider: given more room, a centred
              // box would fill it, and the button would become a slab. The
              // label changes length with the selection; the width follows it
              // rather than jumping.
              child: Align(
                widthFactor: 1,
                child: AnimatedSize(
                  duration: _fade,
                  curve: Curves.easeOut,
                  alignment: Alignment.centerRight,
                  child: Text(
                    widget.primaryLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: widget.labelStyle.copyWith(
                      color: primaryEnabled ? tokens.textHigh : tokens.textXLow,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // The menu around it handles the tap and announces itself; this only
    // names what the chevron is.
    final chevron = Semantics(
      key: DrivesSyncMenu.moreKey,
      label: widget.moreLabel,
      excludeSemantics: true,
      child: _pointer(
        enabled: true,
        onHover: (v) => setState(() => _moreHovered = v),
        onPress: (v) {
          if (_morePressed != v) setState(() => _morePressed = v);
        },
        child: AnimatedContainer(
          duration: _fade,
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _fill(
              tokens,
              enabled: true,
              hovered: _moreHovered,
              pressed: _morePressed,
            ),
          ),
          child: Align(
            widthFactor: 1,
            child: ArDriveIcons.chevronDown(
              size: 16,
              color: tokens.textMid,
            ),
          ),
        ),
      ),
    );

    return AnimatedContainer(
      duration: _fade,
      curve: Curves.easeOut,
      height: widget.height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: outline),
        borderRadius: BorderRadius.circular(ArDriveRadius.control),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(child: primaryHalf),
          AnimatedContainer(duration: _fade, width: 1, color: outline),
          widget.wrapChevron(chevron),
        ],
      ),
    );
  }
}
