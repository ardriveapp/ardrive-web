import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/search/search_box.dart';
import 'package:ardrive/drives_list/domain/drive_list_sort.dart';
import 'package:ardrive/drives_list/presentation/drive_scope_empty.dart';
import 'package:ardrive/drives_list/presentation/drives_sync_menu.dart';
import 'package:ardrive/sync/presentation/sync_loading_indicator.dart';
import 'package:ardrive/sync/presentation/sync_summary.dart';
import 'dart:math' as math;

import 'package:ardrive/app_shell.dart';
import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/components/profile_card.dart';
import 'package:ardrive/components/side_bar.dart';
import 'package:ardrive/drives_list/domain/drive_list_item.dart';
import 'package:ardrive/drives_list/presentation/drive_actions_menu.dart';
import 'package:ardrive/drives_list/presentation/drive_list_row.dart';
import 'package:ardrive/drives_list/presentation/drives_list_cubit.dart';
import 'package:ardrive/drives_list/presentation/open_drive_on_selection.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/components/app_top_bar.dart';
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
import 'package:responsive_builder/responsive_builder.dart';

const double _pagePadding = 16;
const double _sectionGap = 24;
const double _blockGap = 12;

/// The panel's own top and bottom padding, matching the vertical rhythm
/// `ArDriveDataTable` leaves above its header and below its last row.
const double _panelPadding = 8;

/// How far above and below its text the heading's tint reaches. Across, the
/// tint is as wide as the table panel - the width a ticked row's highlight
/// already has - and the page's padding sits inside it, so the title and the
/// sync button stay exactly where they were.
const double _headingInset = 8;

/// The heading's height in both of its forms, so swapping one for the other
/// moves nothing below it.
const double _headingMinHeight = 56;

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
  static Widget provide({required Widget child}) {
    return BlocProvider<DrivesListCubit>(
      create: (context) => DrivesListCubit(
        drivesCubit: context.read<DrivesCubit>(),
        syncCubit: context.read<SyncCubit>(),
        driveDao: context.read<DriveDao>(),
        userPreferencesRepository: context.read<UserPreferencesRepository>(),
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
  Widget? _menuFor(DrivesState drivesState, DriveListItem drive) {
    if (drivesState is! DrivesLoadSuccess) {
      return null;
    }

    for (final owned in drivesState.userDrives) {
      if (owned.id == drive.id) {
        return DriveActionsMenu(drive: owned, isOwner: true);
      }
    }

    for (final shared in drivesState.sharedDrives) {
      if (shared.id == drive.id) {
        return DriveActionsMenu(drive: shared, isOwner: false);
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
              state: state,
              // Selecting is how a drive is opened from anywhere on this route,
              // the sidebar included.
              onOpenDrive: (drive) =>
                  context.read<DrivesCubit>().selectDrive(drive.id),
              onTryAgain: cubit.retryLoadingDrives,
              onSort: cubit.sortBy,
              onToggleSelected: cubit.toggleSelected,
              onToggleSelectAll: cubit.toggleSelectAll,
              onClearSelection: cubit.clearSelection,
              onRetryFailed: cubit.retryFailedDrives,
              onSyncChanged: cubit.syncDrivesWithUnreadChanges,
              buildMenu: (drive) => _menuFor(drivesState, drive),
              syncMenu: const DrivesSyncMenu(),
            );

        final body = bodyWith();

        // The chrome follows the app shell's own desktop/mobile split, because
        // it has to agree with it: the shell wraps the page in a Scaffold on
        // desktop and in nothing at all on mobile, so the drawer and the app
        // bar have to come from here on mobile and must not on desktop. The
        // content inside is a separate decision, made on real width - see
        // [DrivesListBody].
        return ScreenTypeLayout.builder(
          mobile: (context) => Scaffold(
            drawerScrimColor: ArDriveTheme.of(context)
                .themeData
                .colors
                .themeBgSurface
                .withOpacity(0.5),
            drawer: const AppSideBar(),
            appBar: MobileAppBar(
              showSearch: true,
              onSearchNavigateToFolder: (driveId, folderId, {itemId}) =>
                  context.read<AppRouterDelegate>().requestFolder(
                        driveId,
                        folderId,
                        itemId: itemId,
                      ),
            ),
            body: body,
          ),
          desktop: (context) => Padding(
            padding: const EdgeInsets.only(top: 32, right: _pagePadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Search is global - `DriveDao.search` takes no drive id -
                    // so this page had no business being the one screen without
                    // it. Capped and pushed left of the controls, the same shape
                    // the explorer's top bar gives it.
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 400),
                          child: const _DrivesListSearchField(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    const SyncButton(),
                    const SizedBox(width: 8),
                    const SizedBox(width: 8),
                    const ProfileCard(),
                  ],
                ),
                const SizedBox(height: _sectionGap),
                // A click on a drive opens its details on the right, as a
                // click on a row does in the explorer. Desktop only: on a
                // phone a tap opens the drive itself.
                Expanded(
                  child: _DriveDetailsHost(
                    listState: state,
                    drivesState: drivesState,
                    buildBody: bodyWith,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Global search, on the one page that did not have it.
///
/// The field is the explorer's, and so is the sheet it opens. What differs is
/// how a result is reached: the explorer hands the modal its own long-lived
/// `DriveDetailCubit`, which can be told to open a folder in another drive. Here
/// selecting a drive replaces the whole subtree, so that cubit is torn down
/// mid-navigation - hence [AppRouterDelegate.requestFolder], which asks for the
/// folder before the selection that carries it.
class _DrivesListSearchField extends StatelessWidget {
  const _DrivesListSearchField();

  @override
  Widget build(BuildContext context) {
    // Read now, not when a result is picked: going to a drive replaces this
    // page, and a context read after that point would be a dead one.
    final router = context.read<AppRouterDelegate>();

    return SearchBox(
      onNavigateToFolder: (driveId, folderId, {itemId}) =>
          router.requestFolder(driveId, folderId, itemId: itemId),
    );
  }
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
  });

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

    if (state is DrivesListEmpty) {
      return const _DrivesListEmpty();
    }

    // A scope that filters to nothing is not an empty account: the wallet has
    // drives, just none of this kind. `DrivesListEmpty` above is the account
    // with none at all, and says something quite different.
    if (state is DrivesListLoaded && state.drives.isEmpty) {
      return DriveScopeEmpty(scope: state.scope);
    }

    if (state is DrivesListLoaded) {
      return _SelectionShortcuts(
        selecting: state.selected.isNotEmpty,
        onClear: onClearSelection,
        child: _DrivesListLoadedView(
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
            'Create a new drive to start uploading your files.',
            style: typography.paragraphLarge(
              fontWeight: ArFontWeight.semiBold,
              color: colorTokens.textLow,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
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
  });

  final String? chosenDriveId;
  final void Function(String driveId)? onChoose;

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
    return Center(
      child: ConstrainedBox(
        // Past this the columns stop reading as a table: on a 1920 monitor a
        // drive's name and its date sit most of a screen apart.
        constraints: const BoxConstraints(maxWidth: driveListMaxContentWidth),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Decided once, here, for the header and every row - see
            // [driveListShowsColumns]. Measured on the width the list is
            // actually given, which is why the cap is applied above it, and on
            // the reader's text scale, because every one of the five columns
            // is text.
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
                    DecoratedSliver(
                      decoration: BoxDecoration(
                        color: ArDriveTheme.of(context)
                            .themeData
                            .tableTheme
                            .backgroundColor,
                        borderRadius:
                            BorderRadius.circular(cardDefaultBorderRadius),
                      ),
                      sliver: SliverMainAxisGroup(
                        slivers: [
                          // The card's own top and bottom padding, so the
                          // header and the last row are not flush against the
                          // panel's edge.
                          const SliverToBoxAdapter(
                            child: SizedBox(height: _panelPadding),
                          ),
                          SliverToBoxAdapter(
                            child: DriveListHeader(
                              sort: state.sort,
                              sortAscending: state.sortAscending,
                              onSort: onSort,
                              // Offered only where there is room for a column
                              // of checkboxes, and only when something can be
                              // done with a selection.
                              allSelected: onToggleSelectAll == null
                                  ? null
                                  : state.drives.isNotEmpty &&
                                      state.drives.every((drive) =>
                                          state.selected.contains(drive.id)),
                              onToggleSelectAll: onToggleSelectAll,
                              showsAllColumns: showsAllColumns,
                            ),
                          ),
                          _rows(state, showsColumns, showsAllColumns),
                          const SliverToBoxAdapter(
                            child: SizedBox(height: _panelPadding),
                          ),
                        ],
                      ),
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
        ),
      ),
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
          );
        },
        childCount: state.drives.length,
      ),
    );
  }

  Widget _heading(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final selecting = state.selected.isNotEmpty && onClearSelection != null;
    // The table's own colour for a ticked row, so the heading and the rows
    // read as one selection.
    final tint =
        ArDriveTheme.of(context).themeData.tableTheme.selectedItemColor;

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
    return Padding(
      padding: const EdgeInsets.only(top: _pagePadding - _headingInset),
      child: AnimatedContainer(
        duration: _selectionFade,
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(
          horizontal: _pagePadding,
          vertical: _headingInset,
        ),
        constraints: const BoxConstraints(minHeight: _headingMinHeight),
        decoration: BoxDecoration(
          color: selecting ? tint : tint.withOpacity(0),
          borderRadius: BorderRadius.circular(8),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: AnimatedSwitcher(
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
                      : Text(
                          appLocalizationsOf(context).yourDrives,
                          key: const ValueKey('title'),
                          style: typography.heading3(
                            color: colorTokens.textHigh,
                            fontWeight: ArFontWeight.bold,
                          ),
                        ),
                ),
              ),
              if (syncMenu != null) ...[
                const SizedBox(width: 16),
                // Its own width, capped at half the row, so on a narrow screen
                // its label is cut short rather than pushed off the edge: a row
                // hands a child unlimited width, and at 320px and twice the text
                // size "Sync all drives" ran 197px off the screen. A cap rather
                // than a Flexible, which would split the free space with the
                // title and leave the button short of the right edge.
                ConstrainedBox(
                  constraints:
                      BoxConstraints(maxWidth: constraints.maxWidth / 2),
                  child: syncMenu!,
                ),
              ],
            ],
          ),
        ),
      ),
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

/// A drive's details beside Your Drives, the explorer's own panel.
///
/// Which drive is open lives here rather than in the list's cubit: it is a
/// fact about this page's layout, gone when the page is.
///
/// The panel pushes the list narrower, as the explorer's does, while the
/// list can keep its rows as rows - five columns, or three, since the two it
/// drops are what the panel shows. Where it cannot, the panel covers the
/// right of the list instead. Pushing would turn the rows into cards, which
/// are taller, and every row would move under the pointer between the two
/// clicks of a double-click.
///
/// The list sits at the same place in the tree whichever it is, so opening
/// the panel never rebuilds a row: a rebuilt row would forget the first
/// click of a double-click, and its focus.
class _DriveDetailsHost extends StatefulWidget {
  const _DriveDetailsHost({
    required this.listState,
    required this.drivesState,
    required this.buildBody,
  });

  final DrivesListState listState;
  final DrivesState drivesState;
  final Widget Function({
    String? chosenDriveId,
    void Function(String driveId)? onChoose,
  }) buildBody;

  @override
  State<_DriveDetailsHost> createState() => _DriveDetailsHostState();
}

class _DriveDetailsHostState extends State<_DriveDetailsHost> {
  String? _chosenId;

  /// The explorer's width for its panel: a quarter of the window, never less
  /// than this.
  static const _panelMinWidth = 375.0;

  /// The drive whose details are open - only while the list is showing it.
  /// A scope that filters it out, or a drive that goes away, closes them.
  Drive? _chosenDrive() {
    final id = _chosenId;
    final list = widget.listState;
    final drives = widget.drivesState;

    if (id == null ||
        list is! DrivesListLoaded ||
        drives is! DrivesLoadSuccess ||
        !list.drives.any((drive) => drive.id == id)) {
      return null;
    }

    for (final drive in [...drives.userDrives, ...drives.sharedDrives]) {
      if (drive.id == id) {
        return drive;
      }
    }

    return null;
  }

  void _choose(String driveId) {
    if (_chosenId != driveId) {
      setState(() => _chosenId = driveId);
    }
  }

  void _close() {
    if (_chosenId != null) {
      setState(() => _chosenId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final drive = _chosenDrive();

    // A drive the list no longer shows leaves nothing behind to reappear
    // when it comes back.
    if (_chosenId != null && drive == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _chosenDrive() == null) {
          _close();
        }
      });
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _close,
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final panelWidth = math.max(
            _panelMinWidth,
            MediaQuery.sizeOf(context).width * 0.25,
          );
          final textScale = driveListTextScale(
            context,
            ArDriveTypographyNew.of(context).paragraphSmall().fontSize ?? 14,
          );

          final pushes = drive != null &&
              driveDetailsPushList(
                width: constraints.maxWidth,
                panelWidth: panelWidth,
                textScale: textScale,
              );
          final covers = drive != null && !pushes;

          return Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: widget.buildBody(
                      chosenDriveId: drive?.id,
                      onChoose: _choose,
                    ),
                  ),
                  // The explorer's animation, the explorer's width.
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: pushes
                        ? SizedBox(
                            width: panelWidth,
                            child: _panel(context, drive),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
              if (covers)
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: panelWidth,
                  // Over the list, so it needs its own ground and an edge.
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: ArDriveTheme.of(context).themeData.backgroundColor,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                    child: _panel(context, drive),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _panel(BuildContext context, Drive drive) {
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
      onClose: _close,
      // What the drive's own menu on this page does: somebody pressed it, so
      // it is theirs.
      onSync: () =>
          context.read<SyncCubit>().startSyncForDrive(driveId: drive.id),
    );
  }
}
