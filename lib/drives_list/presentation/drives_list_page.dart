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
import 'package:responsive_builder/responsive_builder.dart';

const double _pagePadding = 16;
const double _sectionGap = 24;
const double _blockGap = 12;

/// The panel's own top and bottom padding, matching the vertical rhythm
/// `ArDriveDataTable` leaves above its header and below its last row.
const double _panelPadding = 8;

/// Wide enough for "Sync All Drives" and no wider, at a text scale of 1.
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

        final body = DrivesListBody(
          state: state,
          // Selecting is how a drive is opened from anywhere on this route,
          // the sidebar included.
          onOpenDrive: (drive) =>
              context.read<DrivesCubit>().selectDrive(drive.id),
          onTryAgain: cubit.retryLoadingDrives,
          onSyncAllDrives: cubit.syncAllDrives,
          buildMenu: (drive) => _menuFor(drivesState, drive),
          syncMenu: const DrivesSyncMenu(),
        );

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
            appBar: const MobileAppBar(),
            body: body,
          ),
          desktop: (context) => Padding(
            padding: const EdgeInsets.only(top: 32, right: _pagePadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SyncButton(),
                    SizedBox(width: 8),
                    SizedBox(width: 8),
                    ProfileCard(),
                  ],
                ),
                const SizedBox(height: _sectionGap),
                Expanded(child: body),
              ],
            ),
          ),
        );
      },
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
    required this.onSyncAllDrives,
    this.buildMenu,
    this.syncMenu,
  });

  final DrivesListState state;
  final void Function(DriveListItem drive) onOpenDrive;
  final VoidCallback onTryAgain;
  final VoidCallback onSyncAllDrives;

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
      return _DrivesListLoadedView(
        state: state,
        onOpenDrive: onOpenDrive,
        onSyncAllDrives: onSyncAllDrives,
        buildMenu: buildMenu,
        syncMenu: syncMenu,
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
            'Getting Started',
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
    required this.onSyncAllDrives,
    required this.buildMenu,
    required this.syncMenu,
  });

  final DrivesListLoaded state;
  final void Function(DriveListItem drive) onOpenDrive;
  final VoidCallback onSyncAllDrives;
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
            final showsColumns = driveListShowsColumns(
              constraints.maxWidth,
              textScale: driveListTextScale(
                context,
                ArDriveTypographyNew.of(context).paragraphSmall().fontSize ??
                    14,
              ),
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
                  if (state.nothingHasEverBeenSynced)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(top: _blockGap),
                        child: _SyncEverythingPrompt(
                          isSyncing: state.isSyncing,
                          onSyncAllDrives: onSyncAllDrives,
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: _blockGap)),
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
                          const SliverToBoxAdapter(child: DriveListHeader()),
                          _rows(state, showsColumns),
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
  Widget _rows(DrivesListLoaded state, bool showsColumns) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final drive = state.drives[index];

          return DriveListRow(
            key: ValueKey(drive.id),
            drive: drive,
            showsColumns: showsColumns,
            onTap: () => onOpenDrive(drive),
            menu: buildMenu?.call(drive),
          );
        },
        childCount: state.drives.length,
      ),
    );
  }

  Widget _heading(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _pagePadding,
        _pagePadding,
        _pagePadding,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // No sentence under it. The one it had - "Nothing here has been
          // fetched from the network" - stopped being true the moment opening
          // a drive became the act that fetches it, and a heading that needs a
          // paragraph to explain a list of drives was the wrong heading. What
          // is worth saying about an unfetched account is said once, by the
          // card below, and withdrawn as soon as it stops applying.
          // The heading and the drive-wide actions on one line. The actions
          // were behind the top bar's indicator, which is now present only when
          // there is something to report - so they needed a home that always
          // is, and they act on the drives this page lists.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  appLocalizationsOf(context).yourDrives,
                  style: typography.heading3(
                    color: colorTokens.textHigh,
                    fontWeight: ArFontWeight.bold,
                  ),
                ),
              ),
              if (syncMenu != null) ...[
                const SizedBox(width: 16),
                syncMenu!,
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// The narrowest the sync prompt's text column may be drawn.
///
/// Measured, not chosen: it is the width the card's own title - "Nothing has
/// been synced yet" - occupies as a single line in Wavehaus at
/// `paragraphNormal`/semiBold. `drives_list_sync_prompt_test.dart` loads the
/// real face and takes that measurement rather than trusting a number written
/// here: 173.1px, the desktop face being the wider of the two the page can be
/// drawn in. Below it the title wraps and the two columns stop being a heading
/// beside a button.
///
/// A measurement at a text scale of 1, and multiplied by the reader's scale
/// wherever it is used: the thing it measures is text. The small margin over
/// the measurement is rounding, not headroom, and
/// `drives_list_sync_prompt_test.dart` fails if it ever grows to the point
/// where this has stopped being a measurement.
const double driveListSyncPromptTextMinimum = 210;

/// The narrowest the card may be and still put its button beside its text.
///
/// Derived from the two things that have to fit and the space between them,
/// on the width the card is actually given - which is why the padding it draws
/// inside itself comes off first. Nothing here is picked by eye.
///
/// Both of the things that have to fit are text, so both grow with the
/// reader's text scale and both are handed in already scaled. A breakpoint
/// measured in pixels alone keeps two columns at 2.0 and clips whichever of
/// them loses.
bool driveListSyncPromptShowsColumns(
  double cardWidth, {
  required double textMinimum,
  required double buttonWidth,
}) =>
    cardWidth - _pagePadding * 2 >= textMinimum + _pagePadding + buttonWidth;

/// The one offer this page makes, and only on the one login where it helps.
///
/// With sync-on-login off, a first login lists every drive and can say nothing
/// about any of them. That is the thing the old automatic sync did - so it is
/// offered here, once, rather than assumed.
///
/// Two columns where there is room for two: the words on the left, the one
/// action on the right. Stacked below one another only where two columns
/// genuinely do not fit - and stacked is a fallback here, not the shape the
/// card wants, because a paragraph with a full-width button under it reads as
/// an alert rather than an offer.
///
/// While a sync is actually running it stops being an offer and becomes a
/// report. The words change with it: a card still saying "their contents have
/// not been fetched yet. Sync them all now" beside a strip counting what that
/// very sync has found, above the button it names drawn as unavailable, is
/// three surfaces on one screen with two of them wrong.
class _SyncEverythingPrompt extends StatelessWidget {
  const _SyncEverythingPrompt({
    required this.isSyncing,
    required this.onSyncAllDrives,
  });

  final bool isSyncing;
  final VoidCallback onSyncAllDrives;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    // A sync is running, so the card does not offer to start one. It used to
    // say "their contents have not been fetched yet. Sync them all now" beside
    // a strip reporting "Found 340 items so far..." and under a button it had
    // just named and disabled - three surfaces on one screen, two of them
    // wrong. The offer is only an offer while it can be taken.
    final title = isSyncing
        ? appLocalizationsOf(context).nothingSyncedYetSyncingTitle
        : appLocalizationsOf(context).nothingSyncedYetTitle;
    final description = isSyncing
        ? appLocalizationsOf(context).nothingSyncedYetSyncingDescription
        : appLocalizationsOf(context).nothingSyncedYetDescription;

    final words = Column(
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
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _pagePadding),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Both measurements scaled by what the reader asked for, then the
          // button capped at the room the card actually has: a scaled width
          // wider than the card is a fixed-width box overflowing its parent,
          // which is the same clipped label one layer out.
          final scale = driveListTextScale(
            context,
            typography.paragraphNormal().fontSize ?? 16,
          );
          final available = constraints.maxWidth - _pagePadding * 2;
          final buttonWidth = math.min(
            driveListSyncAllButtonWidth(context),
            available,
          );

          // Measured on the width this card is actually given, in the place
          // that has it. The card is the only thing that has to fit, so it is
          // the only width the decision is allowed to be made on.
          final showsColumns = driveListSyncPromptShowsColumns(
            constraints.maxWidth,
            textMinimum: driveListSyncPromptTextMinimum * scale,
            buttonWidth: buttonWidth,
          );

          final button = ArDriveButtonNew(
            text: appLocalizationsOf(context).syncAllDrives,
            typography: typography,
            variant: ButtonVariant.primary,
            // A width, because without one the button is a SizedBox around a
            // Stack that expands: it took the whole content column, and a slab
            // of primary colour on the one screen whose message is "nothing is
            // wrong yet" reads as an alarm. It is also half of what fixes the
            // breakpoint above.
            maxWidth: buttonWidth,
            // Nothing to start while one is already running. The rows say
            // "Syncing..." for as long as it is. `isDisabled` as well as a
            // null callback: ArDriveButtonNew picks its colours off the flag
            // alone, so without it the button looks live and does nothing -
            // the same present-and-inert failure the menu items are forbidden.
            isDisabled: isSyncing,
            onPressed: isSyncing ? null : onSyncAllDrives,
          );

          return Container(
            decoration: BoxDecoration(
              color: colorTokens.containerL2,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(_pagePadding),
            child: showsColumns
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: words),
                      const SizedBox(width: _pagePadding),
                      button,
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      words,
                      const SizedBox(height: _blockGap),
                      button,
                    ],
                  ),
          );
        },
      ),
    );
  }
}
