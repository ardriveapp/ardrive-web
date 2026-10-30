import 'package:ardrive/locked_drives/presentation/unlock_drive_dialog.dart';
import 'package:ardrive/pages/no_drives/first_drive_page.dart';
import 'package:ardrive/drives_list/domain/drive_list_sort.dart';
import 'package:ardrive/drives_list/domain/drive_scope.dart';
import 'package:ardrive/drives_list/presentation/drive_scope_empty.dart';
import 'package:ardrive/drives_list/presentation/drives_sync_menu.dart';
import 'package:ardrive/sync/presentation/sync_loading_indicator.dart';
import 'package:ardrive/sync/presentation/sync_summary.dart';

import 'package:ardrive/components/list_page/list_page_layout.dart';
import 'package:ardrive/components/list_page/list_table.dart';
import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/drives_list/domain/drive_list_item.dart';
import 'package:ardrive/drives_list/presentation/drive_actions_menu.dart';
import 'package:ardrive/drives_list/presentation/drive_list_row.dart';
import 'package:ardrive/drives_list/presentation/drives_list_cubit.dart';
import 'package:ardrive/drives_list/presentation/open_drive_on_selection.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/no_drives/no_drives_page.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/components/details_panel.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/utils/user_utils.dart';
import 'package:flutter/services.dart';

// The list pages' shared measures (lib/components/list_page/).
const double _pagePadding = listPagePadding;
const double _sectionGap = listPageSectionGap;
const double _blockGap = listPageBlockGap;

/// How long the heading takes to become the selection and back.
const Duration _selectionFade = Duration(milliseconds: 150);

/// Wide enough for "Sync all drives" and no wider, at a text scale of 1.
///
/// The label measures 120px in Wavehaus at the button's size, plus its 20px of
/// padding.
/// Both primary actions on this page. A button that fills its column
/// reads as an alert rather than an offer.
///
/// Never used raw - see [driveListSyncAllButtonWidth]. It is a measurement of
/// text, and text is not a fixed number of pixels.
const double _syncAllButtonWidth = 180;

/// How much larger the reader has asked text to be, as a plain multiplier.
///
/// Taken at the size actually being drawn rather than at 1.0, because a
/// [TextScaler] need not be linear: the platform ones clamp and curve, and
/// scaling a measurement by the wrong end of that curve is how a measured
/// width stops being a measurement.
double driveListTextScale(BuildContext context, double fontSize) {
  if (fontSize <= 0) return 1;

  return MediaQuery.textScalerOf(context).scale(fontSize) / fontSize;
}

/// [_syncAllButtonWidth] at the reader's text scale.
///
/// [ArDriveButtonNew] applies `maxWidth` as a fixed `SizedBox` width and
/// ellipsizes the label inside it, so a constant here is not a maximum - it is
/// the width, and at 2.0 the page's one offer read "Sync All Dri...". The
/// number above was measured at a text scale of 1, so that is the scale it has
/// to be multiplied by.
double driveListSyncAllButtonWidth(BuildContext context) {
  final fontSize =
      ArDriveTypographyNew.of(context).paragraphLarge().fontSize ?? 16;

  return _syncAllButtonWidth * driveListTextScale(context, fontSize);
}

/// Where a login lands: the drives this wallet can open, before any of them is
/// opened.
///
/// The app used to open a drive first and find out about it afterwards, which
/// is where nearly every stranded login came from - "Getting Started" over a
/// list that was still loading, "Drive Not Synced" as a first impression, a
/// blank screen for a bookmarked id. A list has none of those, because the
/// drive list is the one thing a login actually fetches.
///
/// Deep links do not come through here. `/drives/{id}`, a folder link and a
/// file share link open their target directly, exactly as they always have.
class DrivesListPage extends StatelessWidget {
  const DrivesListPage({super.key, required this.onOpenDrive});

  /// Hands the chosen drive to whatever owns navigation, by id.
  ///
  /// Passed in rather than read off a cubit so that opening a drive is an
  /// explicit act: the drives cubit selects a drive on its own the moment the
  /// list loads, and a page that navigated on *that* would close itself before
  /// the user had read it. What navigates is a selection the user made - see
  /// [OpenDriveOnSelection].
  ///
  /// An id rather than a row, because the sidebar can name a drive this page
  /// has no row for yet.
  final void Function(String driveId) onOpenDrive;

  /// The cubit this page reads is provided by the router, above the shell.
  ///
  /// It used to be created here, below `AppShell` - so the sidebar, which is
  /// inside the shell, could not see it. The sidebar now sets the scope this
  /// page filters by, and the two are on opposite sides of that boundary.
  static Widget provide({
    required Widget child,
    DriveScope initialScope = DriveScope.all,
  }) {
    return BlocProvider<DrivesListCubit>(
      create: (context) => DrivesListCubit(
        drivesCubit: context.read<DrivesCubit>(),
        syncCubit: context.read<SyncCubit>(),
        driveDao: context.read<DriveDao>(),
        userPreferencesRepository: context.read<UserPreferencesRepository>(),
        initialScope: initialScope,
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _DrivesListView(onOpenDrive: onOpenDrive);
  }
}

class _DrivesListView extends StatelessWidget {
  const _DrivesListView({required this.onOpenDrive});

  final void Function(String driveId) onOpenDrive;

  /// One way in, for every surface that can choose a drive.
  ///
  /// A row tap and a sidebar tap both go through the drives cubit's selection,
  /// so the two cannot drift into doing different things - which is what they
  /// did when only the row knew how to open anything.
  void _openDrive(BuildContext context, String driveId) {
    // Opening a drive opens it. It never starts a sync, whether or not that
    // drive has ever been walked: a tap in the nav is a request to look at
    // something, not a request to fetch it, and a tap that quietly began
    // minutes of network work was the opposite of the sync-only-when-asked
    // rule the rest of this stack follows.
    //
    // A drive with nothing local lands on `DriveDetailUnsyncedCard`, which
    // says so and carries its own Sync button.
    onOpenDrive(driveId);
  }

  @override
  Widget build(BuildContext context) {
    return OpenDriveOnSelection(
      selections: context.read<DrivesCubit>().driveSelections,
      onOpenDrive: (driveId) => _openDrive(context, driveId),
      child: const _DrivesListChrome(),
    );
  }
}

class _DrivesListChrome extends StatelessWidget {
  const _DrivesListChrome();

  /// The actions menu for one row, or nothing when the drive record it needs
  /// is not in hand.
  ///
  /// [DriveActionsMenu] takes the drive as stored rather than the row's view
  /// of it, because the rename, share, hide and detach dialogs it calls all
  /// take the record itself. Ownership is read the way this page already reads
  /// it: a drive the drives cubit lists as shared is one this wallet does not
  /// own.
  /// Whether this device has the drive's contents: its history was read, or
  /// it holds files of it already (a drive made and uploaded to here).
  static bool _isSynced(DriveListItem drive) =>
      drive.hasBeenWalked || (drive.fileCount ?? 0) > 0;

  Widget? _menuFor(DrivesState drivesState, DriveListItem drive) {
    if (drivesState is! DrivesLoadSuccess) {
      return null;
    }

    for (final owned in drivesState.userDrives) {
      if (owned.id == drive.id) {
        return DriveActionsMenu(
          drive: owned,
          isOwner: true,
          isSynced: _isSynced(drive),
        );
      }
    }

    for (final shared in drivesState.sharedDrives) {
      if (shared.id == drive.id) {
        return DriveActionsMenu(
          drive: shared,
          isOwner: false,
          isSynced: _isSynced(drive),
        );
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DrivesListCubit, DrivesListState>(
      builder: (context, state) {
        final cubit = context.read<DrivesListCubit>();

        // Watched, not read: hiding a drive, renaming one or detaching one all
        // land here as a new drives state, and the menu that offered the
        // action has to redraw with the answer - "Hide" becoming "Unhide"
        // being the one a user would notice immediately.
        final drivesState = context.watch<DrivesCubit>().state;

        Widget bodyWith({
          String? chosenDriveId,
          void Function(String driveId)? onChoose,
        }) =>
            DrivesListBody(
              chosenDriveId: chosenDriveId,
              onChoose: onChoose,
              settingUpFirstDrive: FirstDrivePage.settingUp.value,
              state: state,
              // Selecting is how a drive is opened from anywhere on this route,
              // the sidebar included. A locked drive opens its unlock dialog.
              onOpenDrive: (drive) => drive.isLocked
                  ? showUnlockDriveDialog(context, driveId: drive.id)
                  : context.read<DrivesCubit>().selectDrive(drive.id),
              onTryAgain: cubit.retryLoadingDrives,
              onSort: cubit.sortBy,
              onToggleSelected: cubit.toggleSelected,
              onToggleSelectAll: cubit.toggleSelectAll,
              onClearSelection: cubit.clearSelection,
              onRetryFailed: cubit.retryFailedDrives,
              onSyncChanged: cubit.syncDrivesWithUnreadChanges,
              buildMenu: (drive) => _menuFor(drivesState, drive),
              syncMenu: const DrivesSyncMenu(),
              // A new account gets My files made before it would see this.
              buildEmpty: (_) => FirstDrivePage(
                noDrives: (_) => const _DrivesListEmpty(),
              ),
            );

        // The list pages' shared chrome: on desktop a click on a drive opens
        // its details on the right, as a click on a row does in the
        // explorer; on a phone a tap opens the drive itself.
        // Rebuilt when a new account's first drive starts or stops being
        // set up: the list shows that instead of the half-made drive.
        return ValueListenableBuilder<bool>(
          valueListenable: FirstDrivePage.settingUp,
          builder: (context, _, __) => ListPageChrome(
            desktopChild: ListDetailsHost(
              buildBody: ({chosenId, onChoose}) =>
                  bodyWith(chosenDriveId: chosenId, onChoose: onChoose),
              panelFor: (context, id, close) =>
                  _drivePanel(context, state, drivesState, id, close),
              pushesList: (width, panelWidth, textScale) =>
                  driveDetailsPushList(
                width: width,
                panelWidth: panelWidth,
                textScale: textScale,
              ),
            ),
            child: bodyWith(),
          ),
        );
      },
    );
  }
}

/// A drive's details beside Your drives, the explorer's own panel - only
/// while the list is showing that drive. A scope that filters it out, or a
/// drive that goes away, closes them.
Widget? _drivePanel(
  BuildContext context,
  DrivesListState list,
  DrivesState drives,
  String id,
  VoidCallback close,
) {
  if (list is! DrivesListLoaded ||
      drives is! DrivesLoadSuccess ||
      !list.drives.any((drive) => drive.id == id)) {
    return null;
  }

  for (final drive in [...drives.userDrives, ...drives.sharedDrives]) {
    if (drive.id == id) {
      return DetailsPanel(
        key: ValueKey('drive-details-${drive.id}'),
        item: DriveDataTableItemMapper.fromDrive(
          drive,
          (_) {},
          0,
          isDriveOwner(context.read<ArDriveAuth>(), drive.ownerAddress),
        ),
        currentDrive: drive,
        canNavigateThroughImages: false,
        onClose: close,
        // What the drive's own menu on this page does: somebody pressed it,
        // so it is theirs.
        onSync: () =>
            context.read<SyncCubit>().startSyncForDrive(driveId: drive.id),
      );
    }
  }

  return null;
}

/// The page's content, with none of the chrome around it.
///
/// Split out so all four answers can be rendered - at 320px and at desktop
/// width, in both themes - without standing up the profile card, the sync
/// button and the rest of the shell. Every action is a callback rather than a
/// cubit read for the same reason.
class DrivesListBody extends StatelessWidget {
  const DrivesListBody({
    super.key,
    required this.state,
    required this.onOpenDrive,
    required this.onTryAgain,
    this.onSort,
    this.onToggleSelected,
    this.onToggleSelectAll,
    this.onClearSelection,
    this.onRetryFailed,
    this.onSyncChanged,
    this.buildMenu,
    this.syncMenu,
    this.chosenDriveId,
    this.onChoose,
    this.buildEmpty,
    this.settingUpFirstDrive = false,
  });

  /// What an account with no drives sees, in place of Getting started.
  final WidgetBuilder? buildEmpty;

  /// A new account's first drive is listed but not ready yet: show
  /// [buildEmpty], which says it is being set up, rather than the list.
  final bool settingUpFirstDrive;

  /// The drive whose details are open beside the list, if any.
  final String? chosenDriveId;

  /// A click on a row: show that drive's details. Null where there is no
  /// room for them, which is also how a row knows to show focus instead.
  final void Function(String driveId)? onChoose;

  final DrivesListState state;
  final void Function(DriveListItem drive) onOpenDrive;
  final VoidCallback onTryAgain;

  /// Called with the column whose heading was pressed. Optional so the tests
  /// that only draw the four states need not supply one.
  final void Function(DriveListSort column)? onSort;

  /// Selection, threaded the same way [onSort] is - the page draws what it is
  /// given so its tests need no providers.
  final void Function(String driveId)? onToggleSelected;
  final VoidCallback? onToggleSelectAll;
  final VoidCallback? onClearSelection;
  final VoidCallback? onRetryFailed;
  final VoidCallback? onSyncChanged;

  /// Builds the actions menu for one row, or returns null for a row that has
  /// none.
  ///
  /// A callback for the same reason every other action here is one: the menu
  /// needs the drive record and three app-wide blocs, and this widget exists
  /// so all four answers can be rendered without standing any of that up.
  final Widget? Function(DriveListItem drive)? buildMenu;

  /// The drive-wide sync actions, passed in rather than reached for.
  ///
  /// This widget draws what it is given - which is why its tests need no
  /// providers - and the menu needs `SyncCubit` and `DrivesCubit`. Same rule
  /// as [buildMenu].
  final Widget? syncMenu;

  @override
  Widget build(BuildContext context) {
    final state = this.state;

    if (state is DrivesListUnavailable) {
      return _DrivesListUnavailable(onTryAgain: onTryAgain);
    }

    if (state is DrivesListEmpty ||
        (buildEmpty != null && settingUpFirstDrive)) {
      return buildEmpty?.call(context) ?? const _DrivesListEmpty();
    }

    // A scope that filters to nothing is not an empty account: the wallet has
    // drives, just none of this kind. `DrivesListEmpty` above is the account
    // with none at all, and says something quite different.
    if (state is DrivesListLoaded && state.drives.isEmpty) {
      return DriveScopeEmpty(scope: state.scope);
    }

    if (state is DrivesListLoaded) {
      return _ChoosingSeveral(
        anyTicked: state.selected.isNotEmpty,
        onClear: onClearSelection,
        builder: (context, selecting, onLongPress) => _DrivesListLoadedView(
          state: state,
          onOpenDrive: onOpenDrive,
          buildMenu: buildMenu,
          syncMenu: syncMenu,
          onSort: onSort,
          onToggleSelected: onToggleSelected,
          onToggleSelectAll: onToggleSelectAll,
          onClearSelection: onClearSelection,
          onRetryFailed: onRetryFailed,
          onSyncChanged: onSyncChanged,
          chosenDriveId: chosenDriveId,
          onChoose: onChoose,
          selecting: selecting,
          onLongPress: onLongPress,
        ),
      );
    }

    // Loading, and anything that has not yet resolved into one of the other
    // three. Never "you have none".
    return _DrivesListLoading(
      state: state is DrivesListLoading ? state : null,
    );
  }
}

/// The centred, width-capped column the three non-list states share.
class _CentredMessage extends StatelessWidget {
  const _CentredMessage({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              // The page's own margin, so this panel stops where the table's
              // panel stops rather than running into the window edge.
              padding: const EdgeInsets.fromLTRB(
                _pagePadding,
                _blockGap,
                _pagePadding,
                _sectionGap,
              ),
              child: Container(
                // The ground every other full-panel state sits on. These two -
                // the drives loading, and the drive list that could not be
                // read - were drawn straight onto the page, so the words
                // floated on black while the same states in the explorer had a
                // card behind them.
                decoration: BoxDecoration(
                  color: ArDriveTheme.of(context)
                      .themeData
                      .tableTheme
                      .backgroundColor,
                  borderRadius: BorderRadius.circular(cardDefaultBorderRadius),
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(_sectionGap),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: children,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Still looking. It never says the user has none.
class _DrivesListLoading extends StatelessWidget {
  const _DrivesListLoading({this.state});

  /// Carries how far the drive-list read has got, when there is a figure. Null
  /// where the caller has none - this widget reaches for nothing itself.
  final DrivesListLoading? state;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return _CentredMessage(
      children: [
        Text(
          syncLoadingDrivesLabel(appLocalizationsOf(context), state?.syncState),
          style: typography.heading4(
            color: colorTokens.textHigh,
            fontWeight: ArFontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: _sectionGap),
        // Nothing to measure, so nothing is claimed - it moves and says no
        // more than that. The same mark every other sync surface shows while
        // it works; this used to be a red bar here and a white one in the
        // explorer, for the same wait.
        const SyncLoadingIndicator(),
      ],
    );
  }
}

/// We asked and could not find out.
///
/// Three things it deliberately does not do: claim the user has no drives,
/// offer to create one, and pretend anything is still running.
class _DrivesListUnavailable extends StatelessWidget {
  const _DrivesListUnavailable({required this.onTryAgain});

  final VoidCallback onTryAgain;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return _CentredMessage(
      children: [
        Text(
          appLocalizationsOf(context).driveListUnavailable,
          style: typography.heading4(
            color: colorTokens.textHigh,
            fontWeight: ArFontWeight.bold,
          ),
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
        const SizedBox(height: _sectionGap),
        ArDriveButtonNew(
          text: appLocalizationsOf(context).tryAgain,
          typography: typography,
          variant: ButtonVariant.primary,
          // Without a cap this fills its column - 420px of danger red on the
          // screen whose message is that nothing has been lost. Scaled,
          // because the cap is a measurement of the label inside it.
          maxWidth: driveListSyncAllButtonWidth(context),
          onPressed: onTryAgain,
        ),
      ],
    );
  }
}

/// We looked, and this account really is new. Today's Getting Started, and
/// only ever for this one case.
class _DrivesListEmpty extends StatelessWidget {
  const _DrivesListEmpty();

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(_sectionGap),
      child: Column(
        children: [
          Text(
            'Getting started',
            // heading4, like every other state of this page. At heading2 an
            // empty state was larger than the page's own title.
            style: typography.heading4(
              color: colorTokens.textHigh,
              fontWeight: ArFontWeight.semiBold,
            ),
            textAlign: TextAlign.center,
          ),
          Text(
            appLocalizationsOf(context).gettingStartedBody,
            style: typography.paragraphLarge(
              fontWeight: ArFontWeight.semiBold,
              color: colorTokens.textLow,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          const UploadFirstFilesButton(),
          const SizedBox(height: 32),
          const GettingStartedCards(),
        ],
      ),
    );
  }
}

/// The list itself.
class _DrivesListLoadedView extends StatelessWidget {
  const _DrivesListLoadedView({
    required this.state,
    required this.onOpenDrive,
    required this.buildMenu,
    required this.syncMenu,
    this.onSort,
    this.onToggleSelected,
    this.onToggleSelectAll,
    this.onClearSelection,
    this.onRetryFailed,
    this.onSyncChanged,
    this.chosenDriveId,
    this.onChoose,
    this.selecting = false,
    this.onLongPress,
  });

  final String? chosenDriveId;
  final void Function(String driveId)? onChoose;

  /// Whether the reader is choosing several drives, which shows every row's
  /// box and select-all - see [_ChoosingSeveral].
  final bool selecting;

  /// A long press on a row - see [_ChoosingSeveral].
  final VoidCallback? onLongPress;

  final DrivesListLoaded state;
  final void Function(DriveListItem drive) onOpenDrive;
  final void Function(DriveListSort column)? onSort;
  final void Function(String driveId)? onToggleSelected;
  final VoidCallback? onToggleSelectAll;
  final VoidCallback? onClearSelection;
  final VoidCallback? onRetryFailed;
  final VoidCallback? onSyncChanged;
  final Widget? Function(DriveListItem drive)? buildMenu;

  /// The drive-wide sync actions, passed in rather than reached for.
  ///
  /// This widget draws what it is given - which is why its tests need no
  /// providers - and the menu needs `SyncCubit` and `DrivesCubit`. Same rule
  /// as [buildMenu].
  final Widget? syncMenu;

  @override
  Widget build(BuildContext context) {
    // The full width, like every list page. It was capped at 1200px so a
    // name and its date would not sit a monitor apart; the name column's
    // share and the details panel now take that room on a wide screen.
    return LayoutBuilder(
      builder: (context, constraints) {
        // Decided once, here, for the header and every row - see
        // [driveListShowsColumns]. Measured on the width the list is
        // actually given, and on the reader's text scale, because every
        // one of the five columns is text.
        final textScale = driveListTextScale(
          context,
          ArDriveTypographyNew.of(context).paragraphSmall().fontSize ?? 14,
        );
        final showsAllColumns = driveListShowsColumns(
          constraints.maxWidth,
          textScale: textScale,
        );
        // Three columns wherever five do not fit and three do, not only
        // beside a drive's details. Cards have no checkboxes, headings or
        // sorting, and the sidebar takes enough width that windows from
        // 950 to about 1120px wide got cards and lost Sync selected,
        // while narrower windows without the sidebar kept the table. The
        // two columns dropped, files and created, are in a drive's
        // details.
        final showsColumns = showsAllColumns ||
            driveListShowsCompactColumns(
              constraints.maxWidth,
              textScale: textScale,
            );

        // The whole page scrolls, not just the list inside it. A phone in
        // landscape - 568x264, which is also a portrait phone at a large
        // text scale - has less height than the sync-everything card
        // needs, and a fixed column above a scrolling list gave the list
        // no height at all and nothing to scroll.
        return ArDriveScrollBar(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _heading(context)),
              // Kept while drives are ticked. It used to be withdrawn then,
              // because it carried a red button of its own and two offers
              // of different scopes is the reader having to work out which
              // they meant. It is words now, and taking it away on the
              // first tick moved the whole list up under the pointer.
              if (state.nothingHasEverBeenSynced)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: _blockGap),
                    child: _SyncEverythingPrompt(
                      isSyncing: state.isSyncing,
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: _blockGap)),
              // What the network says changed while the reader was away.
              //
              // Below the never-synced prompt and above the failure banner
              // because it sits between them in urgency: a wallet that has
              // never synced is not owed this news, and a drive that could
              // not be read at all is worse than one that is merely behind.
              //
              // Withdrawn during a sync and while a selection exists, on
              // the same argument as the prompt above: it offers a scope,
              // and two offers of different scopes on one screen is the
              // reader having to work out which one they meant.
              if (state.drivesWithUnreadChanges.isNotEmpty &&
                  !state.isSyncing &&
                  state.selected.isEmpty &&
                  onSyncChanged != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: _blockGap),
                    child: _UnreadChangesBanner(
                      changed: state.drivesWithUnreadChanges.length,
                      onSync: onSyncChanged!,
                    ),
                  ),
                ),
              // A partial failure, said once and fixable in one press.
              // Above the selection bar because it is the more urgent of
              // the two, and below the sync prompt because a wallet that
              // has never synced has no failures to report yet.
              if (state.failedDriveIds.isNotEmpty &&
                  !state.isSyncing &&
                  onRetryFailed != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: _blockGap),
                    child: _PartialFailureBanner(
                      failed: state.failedDriveIds.length,
                      total: state.drives.length,
                      onRetry: onRetryFailed!,
                    ),
                  ),
                ),
              // The panel every other table in the app sits in.
              //
              // `ArDriveDataTable` wraps its header and rows in an
              // `ArDriveCard` on `tableTheme.backgroundColor`; this list
              // drew its rows straight onto the page ground, which is the
              // single biggest reason it read as a different component.
              // Built from slivers rather than a box so the rows stay
              // lazily built and the whole page keeps scrolling as one -
              // a height-bounded container here would be the sidebar's
              // bug over again, with nothing longer than the viewport to
              // scroll.
              //
              // Columns only. On a phone the row is a stacked block with
              // its own rule beneath it, and the explorer's phone view
              // has no panel behind its tiles either.
              if (showsColumns)
                ListTablePanel(
                  header: DriveListHeader(
                    sort: state.sort,
                    sortAscending: state.sortAscending,
                    onSort: onSort,
                    // Offered only where there is room for a column of
                    // checkboxes, and only when something can be done
                    // with a selection.
                    allSelected: onToggleSelectAll == null
                        ? null
                        : state.drives.any((drive) => !drive.isLocked) &&
                            state.drives.every((drive) =>
                                drive.isLocked ||
                                state.selected.contains(drive.id)),
                    onToggleSelectAll: onToggleSelectAll,
                    selecting: selecting,
                    showsAllColumns: showsAllColumns,
                  ),
                  rows: _rows(state, showsColumns, showsAllColumns),
                )
              else
                _rows(state, showsColumns),
              const SliverToBoxAdapter(
                child: SizedBox(height: _sectionGap),
              ),
            ],
          ),
        );
      },
    );
  }

  /// The drive rows, built once and used by both layouts.
  ///
  /// Lazy either way: the panel above wraps this sliver rather than replacing
  /// it with a column of pre-built rows.
  Widget _rows(
    DrivesListLoaded state,
    bool showsColumns, [
    bool showsAllColumns = true,
  ]) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final drive = state.drives[index];

          return DriveListRow(
            key: ValueKey(drive.id),
            drive: drive,
            showsColumns: showsColumns,
            showsAllColumns: showsAllColumns,
            onOpen: () => onOpenDrive(drive),
            chosen: onChoose == null ? null : chosenDriveId == drive.id,
            onChoose: onChoose == null ? null : () => onChoose!(drive.id),
            menu: buildMenu?.call(drive),
            selected: onToggleSelected == null
                ? null
                : state.selected.contains(drive.id),
            onSelectedChanged: onToggleSelected,
            selecting: selecting,
            onLongPress: onLongPress,
          );
        },
        childCount: state.drives.length,
      ),
    );
  }

  Widget _heading(BuildContext context) {
    // Tinted the table's colour for a ticked row while selecting, so the
    // heading and the rows read as one selection.
    final selecting = state.selected.isNotEmpty && onClearSelection != null;

    // The heading and the drive-wide actions on one line. The actions were
    // behind the top bar's indicator, which is now present only when there is
    // something to report - so they needed a home that always is, and they act
    // on the drives this page lists.
    //
    // While drives are ticked the same line becomes the selection: what is
    // ticked, the way out, and - in the sync button at its end - what to do
    // with them. It used to be a band of its own between the cards and the
    // table, which pushed the list down on the first tick and put the count
    // and its action at opposite ends of the screen from the page's other
    // sync button. In place, at the same height, nothing below it moves.
    return ListPageTitleRow(
      highlighted: selecting,
      title: AnimatedSwitcher(
        duration: _selectionFade,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.centerLeft,
          children: [...previous, if (current != null) current],
        ),
        child: selecting
            ? _SelectionHeading(
                key: const ValueKey('selecting'),
                count: state.selected.length,
                onClear: onClearSelection!,
              )
            : ListPageTitleRow.text(
                context,
                appLocalizationsOf(context).yourDrives,
                key: const ValueKey('title'),
              ),
      ),
      action: syncMenu,
    );
  }
}

/// The heading while drives are ticked: the way out, then how many.
///
/// The x first, where the eye lands, as mail and file lists put it. Esc does
/// the same - see [_SelectionShortcuts].
class _SelectionHeading extends StatelessWidget {
  const _SelectionHeading({
    super.key,
    required this.count,
    required this.onClear,
  });

  final int count;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Row(
      children: [
        ArDriveIconButton(
          icon: ArDriveIcons.x(size: 20, color: colorTokens.textHigh),
          tooltip: appLocalizationsOf(context).driveListClearSelectionTooltip,
          onPressed: onClear,
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            appLocalizationsOf(context).driveListSelectedCount(count),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: typography.paragraphLarge(
              color: colorTokens.textHigh,
              fontWeight: ArFontWeight.semiBold,
            ),
          ),
        ),
      ],
    );
  }
}

/// What a first login is owed: the list is every drive, and nothing about any
/// of them is known yet.
///
/// With sync-on-login off, a first login lists every drive and can say nothing
/// about any of them. That is the thing the old automatic sync did - so it is
/// said here, once, rather than assumed.
///
/// Words only. It carried a red "Sync all drives" of its own, a hundred pixels
/// below the page's sync button saying much the same - and while drives were
/// ticked, a third red button in the selection bar. The page's sync button now
/// turns red and reads "Sync all drives" for as long as this card is shown, so
/// the card says why and the button, right above it, is how.
///
/// While a sync is actually running it stops being an offer and becomes a
/// report. The words change with it: a card still saying "Sync your drives"
/// beside a strip counting what that very sync has found is two surfaces on
/// one screen with one of them wrong.
class _SyncEverythingPrompt extends StatelessWidget {
  const _SyncEverythingPrompt({required this.isSyncing});

  final bool isSyncing;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    final title = isSyncing
        ? appLocalizationsOf(context).nothingSyncedYetSyncingTitle
        : appLocalizationsOf(context).nothingSyncedYetTitle;
    final description = isSyncing
        ? appLocalizationsOf(context).nothingSyncedYetSyncingDescription
        : appLocalizationsOf(context).nothingSyncedYetDescription;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _pagePadding),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: colorTokens.containerL2,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(_pagePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: typography.paragraphNormal(
                color: colorTokens.textHigh,
                fontWeight: ArFontWeight.semiBold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: typography.paragraphSmall(
                color: colorTokens.textLow,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Esc ends a selection, as in every list with checkboxes.
///
/// Bound only while there is a selection, so otherwise Esc reaches whatever is
/// around the list - the drive details panel closes on it. A shortcut is only
/// heard from where focus is, and ticking a checkbox gives nothing focus, so
/// the list holds focus until something else - the search box, a dialog -
/// takes it.
class _SelectionShortcuts extends StatelessWidget {
  const _SelectionShortcuts({
    required this.selecting,
    required this.onClear,
    required this.child,
  });

  final bool selecting;
  final VoidCallback? onClear;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final onClear = this.onClear;

    // The shortcut above the focus, not inside it: a key travels up from
    // where focus is, so a handler below the focused node never hears it.
    return CallbackShortcuts(
      bindings: {
        if (selecting && onClear != null)
          const SingleActivator(LogicalKeyboardKey.escape): onClear,
      },
      child: Focus(
        autofocus: true,
        skipTraversal: true,
        child: child,
      ),
    );
  }
}

/// Whether the reader is choosing several drives, which shows every row's
/// checkbox and select-all: the explorer's rule, [ArDriveMultiSelect].
///
/// Once a drive is ticked, while the multi-select key is held (Cmd on macOS
/// and iOS, Ctrl everywhere else), or after a long press on a touch screen.
/// Outside it, a row's box shows while the pointer is on the row or it has
/// focus. Ticking still means only one thing here: the drives Sync selected
/// acts on. A click on a row only chooses it; only a click on the box, or
/// Space on the focused row, ticks.
class _ChoosingSeveral extends StatefulWidget {
  const _ChoosingSeveral({
    required this.anyTicked,
    required this.onClear,
    required this.builder,
  });

  final bool anyTicked;

  /// Clears the ticks.
  final VoidCallback? onClear;
  final Widget Function(
    BuildContext context,
    bool selecting,
    VoidCallback onLongPress,
  ) builder;

  @override
  State<_ChoosingSeveral> createState() => _ChoosingSeveralState();
}

class _ChoosingSeveralState extends State<_ChoosingSeveral> {
  bool _longPressed = false;

  @override
  void didUpdateWidget(_ChoosingSeveral oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A long press opens the checkboxes until the selection empties again -
    // the last box unticked, the x or Esc - as the explorer's does.
    if (oldWidget.anyTicked && !widget.anyTicked) {
      _longPressed = false;
    }
  }

  void _onLongPress() => setState(() => _longPressed = !_longPressed);

  /// Esc ends choosing several, ticked or not, as it does in the explorer: a
  /// long press with nothing ticked yet is ended by it too.
  void _end() {
    setState(() => _longPressed = false);
    if (widget.anyTicked) widget.onClear?.call();
  }

  @override
  Widget build(BuildContext context) {
    final choosing = widget.anyTicked || _longPressed;

    return _SelectionShortcuts(
      selecting: choosing,
      onClear:
          choosing && (widget.onClear != null || _longPressed) ? _end : null,
      child: ArDriveMultiSelectKey(
        builder: (context, keyHeld) => widget.builder(
          context,
          ArDriveMultiSelect.isSelecting(
            anyTicked: widget.anyTicked,
            keyHeld: keyHeld,
            longPressed: _longPressed,
          ),
          _onLongPress,
        ),
      ),
    );
  }
}

/// A sync that read some drives and not others, and the one press that fixes
/// it.
///
/// The failure was already on each row and in the sync menu; what was missing
/// was the sentence that adds them up and the button that acts on exactly that
/// set. A reader should not have to count red triangles to find out how bad it
/// was, nor open a menu to retry what broke.
/// Tells a returning reader that the drives on screen have moved on.
///
/// The whole point of this page is that its figures come from the local
/// database and nothing else, which is what makes it instant - and also what
/// makes it silently old. A reader who closed the tab on Tuesday and came back
/// on Friday sees Tuesday's file counts rendered with exactly the confidence of
/// current ones, and the only cue is a `Last synced` cell they have to read and
/// do arithmetic on.
///
/// So this says the one thing the table cannot: not that the numbers are old -
/// they always are - but that they are *wrong*, because the drives themselves
/// have changed. That is a fact worth interrupting for, and it is only ever
/// shown when the network has confirmed it. Nothing changed means nothing said.
///
/// Deliberately quieter than [_PartialFailureBanner]: nothing here has gone
/// wrong, and neutral is what separates news from an alarm.
class _UnreadChangesBanner extends StatelessWidget {
  const _UnreadChangesBanner({
    required this.changed,
    required this.onSync,
  });

  final int changed;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _pagePadding),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ArDriveTheme.of(context).themeData.tableTheme.backgroundColor,
          borderRadius: BorderRadius.circular(cardDefaultBorderRadius),
          border: Border.all(color: colorTokens.strokeLow),
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          spacing: 16,
          runSpacing: 12,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ArDriveIcons.cloudSync(
                        size: 16,
                        color: colorTokens.iconHigh,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          appLocalizationsOf(context)
                              .driveListDrivesHaveChanges(changed),
                          style: typography.paragraphNormal(
                            color: colorTokens.textHigh,
                            fontWeight: ArFontWeight.semiBold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Says what the figures below still are, rather than leaving
                  // a reader to wonder whether they are looking at nothing.
                  Text(
                    appLocalizationsOf(context)
                        .driveListDrivesHaveChangesDetail,
                    style: typography.paragraphSmall(
                      color: colorTokens.textLow,
                    ),
                  ),
                ],
              ),
            ),
            ArDriveButtonNew(
              text: appLocalizationsOf(context)
                  .driveListSyncThoseWithChanges(changed),
              typography: typography,
              variant: ButtonVariant.primary,
              size: ArDriveButtonSize.compact,
              onPressed: onSync,
            ),
          ],
        ),
      ),
    );
  }
}

class _PartialFailureBanner extends StatelessWidget {
  const _PartialFailureBanner({
    required this.failed,
    required this.total,
    required this.onRetry,
  });

  final int failed;
  final int total;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _pagePadding),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ArDriveTheme.of(context).themeData.tableTheme.backgroundColor,
          borderRadius: BorderRadius.circular(cardDefaultBorderRadius),
          border: Border.all(color: colorTokens.strokeRed),
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          spacing: 16,
          runSpacing: 12,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ArDriveIcons.triangle(
                        size: 16,
                        color: colorTokens.strokeRed,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          appLocalizationsOf(context)
                              .driveListSomeCouldNotBeRead(failed, total),
                          style: typography.paragraphNormal(
                            color: colorTokens.textHigh,
                            fontWeight: ArFontWeight.semiBold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Says what is still true as well as what went wrong: a
                  // drive that could not be reached is not a drive that lost
                  // anything, and a reader looking at red needs telling.
                  Text(
                    appLocalizationsOf(context)
                        .driveListSomeCouldNotBeReadDetail,
                    style: typography.paragraphSmall(
                      color: colorTokens.textLow,
                    ),
                  ),
                ],
              ),
            ),
            ArDriveButtonNew(
              text: appLocalizationsOf(context)
                  .driveListSyncThoseThatFailed(failed),
              typography: typography,
              variant: ButtonVariant.primary,
              size: ArDriveButtonSize.compact,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
