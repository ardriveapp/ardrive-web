import 'package:ardrive/drives_list/presentation/drives_list_cubit.dart';
import 'package:ardrive/drives_list/domain/drive_scope.dart';
import 'package:ardrive/drives_list/presentation/drive_scope_rail.dart';
// ignore_for_file: use_build_context_synchronously

import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/blocs/hide/global_hide_bloc.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/components/app_version_widget.dart';
import 'package:ardrive/components/copy_button.dart';
import 'package:ardrive/components/new_button/new_button.dart';
import 'package:ardrive/dev_tools/app_dev_tools.dart';
import 'package:ardrive/main.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/sync/presentation/sync_history_panel.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive/utils/size_constants.dart';
import 'package:ardrive_logger/ardrive_logger.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

/// The nav's way back to the drives list.
///
/// Named so a test can find it in either of the two shapes it is drawn in -
/// with its label on the drawer and the expanded rail, and as a bare icon on
/// the collapsed one, where there is no text to look for.

class AppSideBar extends StatefulWidget {
  const AppSideBar({super.key});

  @override
  State<AppSideBar> createState() => _AppSideBarState();
}

class _AppSideBarState extends State<AppSideBar> {
  bool _isExpanded = true;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ArDriveTheme.of(context).themeData.backgroundColor,
      child: ScreenTypeLayout.builder(
        mobile: (context) => _mobileView(),
        desktop: (context) => _desktopView(),
      ),
    );
  }

  Widget _mobileView() {
    return Drawer(
      backgroundColor: ArDriveTheme.of(context).themeData.backgroundColor,
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.75,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    const SizedBox(
                      height: kIsWeb ? 0 : 39,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Align(
                            alignment: Alignment.centerLeft,
                            child: _buildLogo(true)),
                        ArDriveIconButton(
                          icon: ArDriveIcons.menu(
                            size: defaultIconSize,
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeFgDefault,
                          ),
                          onPressed: () => Scaffold.of(context).closeDrawer(),
                        ),
                      ],
                    ),
                    const SizedBox(
                      height: 16,
                    ),
                    _buildDriveActionsButton(
                      context,
                      true,
                    ),
                    const SizedBox(
                      height: 16,
                    ),
                    _buildDriveNav(isMobile: true),
                  ],
                ),
              ),
              const SizedBox(
                height: 16,
              ),
              if ((AppPlatform.isMobile || AppPlatform.isMobileWeb()) &&
                  configService.flavor != Flavor.production) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 16.0),
                  child: GestureDetector(
                    child: Text(
                      'Open dev tools',
                      style: ArDriveTypography.body
                          .buttonNormalBold()
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    onTap: () {
                      ArDriveDevTools().showDevTools();
                    },
                  ),
                ),
                const SizedBox(
                  height: 16,
                ),
              ],
              const Padding(
                padding: EdgeInsets.only(left: 20.0),
                child: AppVersionWidget(),
              ),
              const SizedBox(
                height: 32,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _desktopView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ArDriveScrollBar(
          controller: _scrollController,
          child: SingleChildScrollView(
            controller: _scrollController,
            child: Container(
              // A minimum, not a fixed height. Pinned to exactly the viewport
              // the scroll view had nothing longer than itself to scroll, so
              // an expanded scope with a long drive list simply overflowed and
              // clipped - the private drives were unreachable without first
              // collapsing the public ones. IntrinsicHeight keeps the Expanded
              // below working, so a short sidebar still pushes its footer down.
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: ArDriveTheme.of(context).themeData.colors.shadow,
                    width: 1,
                  ),
                ),
              ),
              child: IntrinsicHeight(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  child: SizedBox(
                    width: _isExpanded ? 240 : 64,
                    child: Column(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              const SizedBox(
                                height: 24,
                              ),
                              _buildLogo(false),
                              const SizedBox(
                                height: 24,
                              ),
                              _buildDriveActionsButton(
                                context,
                                false,
                              ),
                              const SizedBox(
                                height: 16,
                              ),
                              _buildDriveNav(isMobile: false),
                            ],
                          ),
                        ),
                        const SizedBox(
                          height: 16,
                        ),
                        _isExpanded
                            ? const SizedBox(
                                height: 16,
                              )
                            : const Spacer(),
                        _buildSideBarBottom(),
                      ],
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

  /// The way back to the list of drives.
  ///
  /// Above the drive list because it is navigation and that is what this
  /// column is for, and because the list of everything is where every file
  /// manager puts it: over the things it contains, not beside them.
  ///
  /// The drive the user came from stays selected underneath it - see
  /// [AppRouterDelegate.showDrivesList] - so this is a round trip of one tap
  /// each way rather than a door that closes behind them.
  /// What the nav shows: scopes while the drives list is the page, the drives
  /// themselves everywhere else.
  ///
  /// The two never both apply. On the drives list the table already lists every
  /// drive with columns to explain itself, so listing them again on the left
  /// was the same answer twice - and it pushed Private and Shared below however
  /// many public drives the wallet had, off screen on any real account. Inside
  /// a drive the list is the switcher, duplicates nothing, and stays as it was.
  Widget _buildDriveNav({required bool isMobile}) {
    // The router's own predicate, not the raw flag. `showingDrivesList` is a
    // request; whether it is honoured also depends on the profile, and for a
    // logged-out viewer following a share link it is not - the explorer shell
    // is built instead, and `DrivesListCubit` is never provided. Reading the
    // flag alone had this nav render scopes, and the All Drives row watch a
    // cubit that did not exist, which threw and left the whole sidebar grey.
    final canGoToDrivesList = AppRouterDelegate.canShowDrivesList(
      context.watch<ProfileCubit>().state,
    );
    final showsScopes = context.watch<AppRouterDelegate>().showingDrivesList &&
        canGoToDrivesList;
    final showLabels = isMobile || _isExpanded;

    // The one row that never moves.
    //
    // The nav used to swap wholesale between the two screens, so nothing stayed
    // put to orient against - and the only way home was the logo, which is a
    // convention rather than an affordance: no label, no hint, and the person
    // who built the app did not find it. This row is labelled, it is where a
    // reader is already looking, and it is in the same place on every screen.
    // Offered only to somebody who has a drives list to go to - the same rule
    // the logo uses, and for the same reason.
    final home = canGoToDrivesList
        ? _AllDrivesRow(
            showLabel: showLabels,
            isOnDrivesList: showsScopes,
          )
        : const SizedBox.shrink();

    if (showsScopes) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          home,
          const SizedBox(height: 6),
          Divider(
            height: 1,
            color: ArDriveTheme.of(context).themeData.colorTokens.strokeLow,
          ),
          const SizedBox(height: 6),
          DriveScopeRail(showLabels: showLabels),
        ],
      );
    }

    // The collapsed rail is 64px wide and has never shown drive names.
    if (!isMobile && !_isExpanded) {
      return const SizedBox();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        home,
        const SizedBox(height: 6),
        Divider(
          height: 1,
          color: ArDriveTheme.of(context).themeData.colorTokens.strokeLow,
        ),
        const SizedBox(height: 6),
        BlocBuilder<DrivesCubit, DrivesState>(
          builder: (context, state) {
            if (state is DrivesLoadSuccess &&
                (state.userDrives.isNotEmpty ||
                    state.sharedDrives.isNotEmpty)) {
              final accordion = _Accordion(state: state, isMobile: isMobile);

              return Flexible(
                child: isMobile
                    ? accordion
                    : Padding(
                        padding: const EdgeInsets.only(left: 43.0),
                        child: accordion,
                      ),
              );
            }

            // Nothing while the list is being read. The nav is where a reader
            // looks for drives, not for a report on fetching them.
            return const SizedBox();
          },
        ),
      ],
    );
  }

  Widget _buildLogo(bool isMobile) {
    // The way home, which is what a logo is on the web and what this one was
    // not: it sat inert at the top of the nav while a house was added beside
    // the wallet address, in the cluster that is about the account rather than
    // about where you are.
    //
    // Only for somebody who has a drives list to go to - the same predicate the
    // router uses before it will draw one.
    final goesHome = AppRouterDelegate.canShowDrivesList(
      context.watch<ProfileCubit>().state,
    );

    if (!goesHome) {
      return _logoImage(isMobile);
    }

    return ArDriveClickArea(
      tooltip: appLocalizationsOf(context).allDrivesScope,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (Scaffold.maybeOf(context) != null) {
            Scaffold.of(context).closeDrawer();
          }

          context.read<AppRouterDelegate>().showDrivesList();
        },
        child: _logoImage(isMobile),
      ),
    );
  }

  Widget _logoImage(bool isMobile) {
    return SizedBox(
      height: 64,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _isExpanded
            ? Padding(
                padding: EdgeInsets.all(isMobile ? 0 : 16.0),
                child: Image.asset(
                  // TODO: replace with ArDriveTheme .isLight method
                  ArDriveTheme.of(context).themeData.name == 'light'
                      ? Resources.images.brand.blackLogo1
                      : Resources.images.brand.whiteLogo1,
                  height: 32,
                  fit: BoxFit.contain,
                ),
              )
            : ArDriveImage(
                width: 42,
                height: 42,
                image: AssetImage(
                  Resources.images.brand.logo1,
                ),
              ),
      ),
    );
  }

  Widget _buildSideBarBottom() {
    return _isExpanded
        ? Padding(
            padding: const EdgeInsets.only(
              left: 43.0,
              right: 24,
              bottom: 24,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 8,
                        ),
                        Padding(
                          padding: EdgeInsets.only(left: 5.0),
                          child: AppVersionWidget(),
                        ),
                      ],
                    ),
                    AnimatedScale(
                      duration: const Duration(milliseconds: 200),
                      scale: _isExpanded ? 1 : 0,
                      child: ArDriveIconButton(
                        onPressed: () {
                          setState(() {
                            _isExpanded = !_isExpanded;
                          });
                        },
                        tooltip: appLocalizationsOf(context).collapseSideBar,
                        icon: ArDriveIcons.arrowLeftFilled(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          )
        : Column(
            children: [
              ArDriveIconButton(
                tooltip: appLocalizationsOf(context).expandSideBar,
                icon: ArDriveIcons.arrowRightFilled(),
                onPressed: () {
                  setState(() {
                    _isExpanded = !_isExpanded;
                  });
                },
              ),
              const SizedBox(
                height: 32,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.0),
                child: AppVersionWidget(),
              ),
              const SizedBox(
                height: 32,
              ),
            ],
          );
  }

  Widget _buildDriveActionsButton(
    BuildContext context,
    bool isMobile,
  ) {
    final profileState = context.watch<ProfileCubit>().state;

    if (profileState is ProfileLoggedIn) {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Column(
          children: [
            Align(
              alignment: Alignment.center,
              child: _newButton(_isExpanded, isMobile),
            ),
          ],
        ),
      );
    } else {
      return _newButton(_isExpanded, isMobile);
    }
  }

  Widget _newButton(
    bool isExpanded,
    bool isMobile,
  ) {
    Drive? currentDrive;
    FolderWithContents? currentFolder;
    final state = context.watch<DriveDetailCubit>().state;

    if (state is DriveDetailLoadSuccess) {
      currentDrive = state.currentDrive;
      currentFolder = state.folderInView;
    }

    return ArDriveClickArea(
      tooltip: appLocalizationsOf(context).showMenu,
      child: NewButton(
        anchor: isMobile
            ? const Aligned(
                follower: Alignment.topLeft,
                target: Alignment.bottomLeft,
              )
            : const Aligned(
                follower: Alignment.topLeft,
                target: Alignment.topRight,
              ),
        drive: currentDrive,
        driveDetailState: context.read<DriveDetailCubit>().state,
        currentFolder: currentFolder,
        customOffset: _isExpanded ? null : const Offset(52, -40),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Container(
              width: isMobile
                  ? constraints.maxWidth
                  : _isExpanded
                      ? 128
                      : 40,
              height: 40,
              decoration: BoxDecoration(
                color:
                    ArDriveTheme.of(context).themeData.colors.themeAccentBrand,
                shape: _isExpanded ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: _isExpanded
                    ? BorderRadius.all(
                        Radius.circular(isMobile ? 5 : 8),
                      )
                    : null,
              ),
              child: isExpanded
                  ? Center(
                      child: Text(
                        appLocalizationsOf(context).newString,
                        style: ArDriveTypography.headline.headline5Bold(
                          color: Colors.white,
                        ),
                      ),
                    )
                  : ArDriveIcons.plus(color: Colors.white),
            );
          },
        ),
      ),
    );
  }
}

/// The way back to the list of drives, in the nav, above the drives.
///
/// `showingDrivesList` used to be set in exactly one place - on login - so a
/// user who opened a drive could not get back to the list without the
/// browser's back button or typing the address. This is the way back, and it
/// is a route rather than a re-render: the address bar reads `/drives`
/// afterwards, so a bookmark and the browser's own history agree with what is
/// on screen.
///
/// Not drawn as selected, ever. The drive the user came from keeps the
/// selection underneath - that is what makes returning to it one tap - and two
/// highlighted rows would be two claims about where they are.

class DriveListTile extends StatelessWidget {
  final Drive drive;
  final bool hasAlert;
  final bool isSelected;
  final bool isHidden;
  final VoidCallback onTap;

  const DriveListTile({
    super.key,
    required this.drive,
    required this.isSelected,
    required this.onTap,
    required this.isHidden,
    this.hasAlert = false,
  });

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return GestureDetector(
      key: key,
      onTap: onTap,
      child: Container(
        decoration: isSelected
            ? BoxDecoration(
                color: colorTokens.containerL1,
                borderRadius: BorderRadius.circular(4),
              )
            : null,
        padding: const EdgeInsets.only(
          left: 10.0,
          right: 8.0,
          top: 2.0,
          bottom: 2.0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          mainAxisSize: MainAxisSize.max,
          children: [
            Flexible(
              child: HoverWidget(
                hoverScale: 1,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(
                      child: Text(
                        drive.name,
                        style: isSelected
                            ? typography.paragraphNormal(
                                fontWeight: ArFontWeight.semiBold,
                              )
                            : typography.paragraphNormal(
                                fontWeight: ArFontWeight.semiBold,
                                color: isHidden
                                    ? colorTokens.textLow
                                    : ArDriveTheme.of(context)
                                        .themeData
                                        .colorTokens
                                        .textMid,
                              ),
                      ),
                    ),
                    if (isHidden) ...{
                      const SizedBox(width: 8),
                      ArDriveIcons.eyeClosed(
                          size: 16, color: colorTokens.textLow),
                    },
                  ],
                ),
              ),
            ),
            if (hasAlert) ...{
              const SizedBox(width: 8),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: ArDriveTheme.of(context)
                      .themeData
                      .colors
                      .themeErrorOnEmphasis,
                  shape: BoxShape.circle,
                ),
              ),
            }
          ],
        ),
      ),
    );
  }
}

Future<void> showSupportModal({
  required BuildContext context,
}) async {
  final typography = ArDriveTypographyNew.of(context);
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
  final logExportInfo = LogExportInfo(
    emailSubject: appLocalizationsOf(context).shareLogsEmailSubject,
    emailBody: appLocalizationsOf(context).shareLogsEmailBody,
    shareText: appLocalizationsOf(context).shareLogsNativeShareText,
    shareSubject: appLocalizationsOf(context).shareLogsNativeShareSubject,
    emailSupport: Resources.emailSupport,
  );

  showArDriveDialog(
    context,
    content: ArDriveStandardModalNew(
      hasCloseButton: true,
      title: appLocalizationsOf(context).help,
      // Taller than the screen on a phone at a large text scale. Bounded and
      // scrolling rather than clipped: the Download button at the bottom is
      // the reason a user opened this, and it must stay reachable.
      scrollableContent: true,
      content: SizedBox(
        width: 384,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appLocalizationsOf(context).needHelpReachOut,
              style: typography.paragraphLarge(
                fontWeight: ArFontWeight.semiBold,
                color: colorTokens.textHigh,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              appLocalizationsOf(context).email,
              style: typography.paragraphNormal(
                fontWeight: ArFontWeight.bold,
                color: colorTokens.textHigh,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    Resources.emailSupport,
                    style: typography.paragraphNormal(
                      color: colorTokens.textMid,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const CopyButton(
                  text: Resources.emailSupport,
                  showCopyText: false,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              appLocalizationsOf(context).resources,
              style: typography.paragraphNormal(
                fontWeight: ArFontWeight.bold,
                color: colorTokens.textHigh,
              ),
            ),
            const SizedBox(height: 12),
            ArDriveClickArea(
              child: GestureDetector(
                onTap: () {
                  openUrl(url: Resources.helpCenterLink);
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Flexible: at 320px and text scale 2.0 these labels are
                    // wider than the modal that holds them, and a Row with
                    // nothing that can give overflows by the difference.
                    Flexible(
                      child: Text(
                        appLocalizationsOf(context).helpCenter,
                        style: typography.paragraphNormal(
                          color: colorTokens.textLink,
                          fontWeight: ArFontWeight.semiBold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    ArDriveIcons.arrowRightOutline(
                      size: 14,
                      color: colorTokens.textLink,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            ArDriveClickArea(
              child: GestureDetector(
                onTap: () {
                  openUrl(url: Resources.discordLink);
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Flexible: at 320px and text scale 2.0 these labels are
                    // wider than the modal that holds them, and a Row with
                    // nothing that can give overflows by the difference.
                    Flexible(
                      child: Text(
                        appLocalizationsOf(context).discord,
                        style: typography.paragraphNormal(
                          color: colorTokens.textLink,
                          fontWeight: ArFontWeight.semiBold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    ArDriveIcons.arrowRightOutline(
                      size: 14,
                      color: colorTokens.textLink,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            ArDriveClickArea(
              child: GestureDetector(
                onTap: () {
                  openUrl(url: Resources.docsLink);
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Flexible: at 320px and text scale 2.0 these labels are
                    // wider than the modal that holds them, and a Row with
                    // nothing that can give overflows by the difference.
                    Flexible(
                      child: Text(
                        appLocalizationsOf(context).developerDocs,
                        style: typography.paragraphNormal(
                          color: colorTokens.textLink,
                          fontWeight: ArFontWeight.semiBold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    ArDriveIcons.arrowRightOutline(
                      size: 14,
                      color: colorTokens.textLink,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              appLocalizationsOf(context).troubleshooting,
              style: typography.paragraphNormal(
                fontWeight: ArFontWeight.bold,
                color: colorTokens.textHigh,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              appLocalizationsOf(context).troubleshootingDescription,
              style: typography.paragraphSmall(
                color: colorTokens.textMid,
              ),
            ),
            // A door to the sync record rather than the record itself: it
            // has its own modal now. Embedded here it was the sixth section
            // of a page about support email, Help Center, Discord and Docs,
            // and a reader had to scroll past all of them to reach it.
            const SizedBox(height: 12),
            ArDriveClickArea(
              child: GestureDetector(
                // Opened over Help rather than in place of it: popping and
                // pushing in one frame loses the push, and a reader who came
                // for the logs gets Help back when they close the record.
                onTap: () => showSyncHistoryModal(context),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        appLocalizationsOf(context).syncHistory,
                        style: typography.paragraphNormal(
                          color: colorTokens.textLink,
                          fontWeight: ArFontWeight.semiBold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    ArDriveIcons.arrowRightOutline(
                      size: 14,
                      color: colorTokens.textLink,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        ModalAction(
          action: () async {
            await logger.exportLogs(info: logExportInfo);
            if (context.mounted) {
              showArDriveDialog(
                context,
                content: ArDriveStandardModalNew(
                  hasCloseButton: true,
                  title: 'Logs Exported',
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Logs exported successfully',
                        style: typography.paragraphNormal(
                          fontWeight: ArFontWeight.semiBold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Logs can be found in your application directory',
                        style: typography.paragraphNormal(),
                      ),
                    ],
                  ),
                  actions: [
                    ModalAction(
                      action: () {
                        Navigator.pop(context);
                      },
                      title: 'OK',
                    ),
                  ],
                ),
              );
            }
          },
          title: appLocalizationsOf(context).download,
        ),
      ],
    ),
  );
}

class _Accordion extends StatelessWidget {
  const _Accordion({required this.state, required this.isMobile});

  final DrivesLoadSuccess state;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return BlocBuilder<GlobalHideBloc, GlobalHideState>(
      builder: (context, hideState) {
        return ArDriveAccordion(
          contentPadding: isMobile ? const EdgeInsets.all(4) : null,
          backgroundColor: ArDriveTheme.of(context).themeData.backgroundColor,
          children: [
            if (state.userDrives.isNotEmpty)
              ArDriveAccordionItem(
                isExpanded: true,
                Text(
                  appLocalizationsOf(context).publicDrives.toUpperCase(),
                  style: typography.paragraphNormal(
                    fontWeight: ArFontWeight.semiBold,
                    color: colorTokens.textHigh,
                  ),
                ),
                state.userDrives
                    .where((element) {
                      final isHidden = hideState is HiddingItems;

                      return element.isPublic &&
                          (isHidden ? !element.isHidden : true);
                    })
                    .map(
                      (d) => DriveListTile(
                        hasAlert: state.drivesWithAlerts.contains(d.id),
                        drive: d,
                        onTap: () {
                          _closeDrawer(context);

                          if (state.selectedDriveId == d.id) {
                            // opens the root folder
                            context.read<DriveDetailCubit>().openFolder();
                          }

                          // Selecting an already-selected drive changes no
                          // state, and used to return here. That left the tap
                          // silent on the drives list, where the selected
                          // drive is not what is on screen - the list is, and
                          // it opens a drive when one is chosen.
                          context.read<DrivesCubit>().selectDrive(d.id);
                        },
                        isSelected: state.selectedDriveId == d.id,
                        isHidden: d.isHidden,
                      ),
                    )
                    .toList(),
              ),
            if (state.userDrives.isNotEmpty)
              ArDriveAccordionItem(
                isExpanded: true,
                Text(
                  appLocalizationsOf(context).privateDrives.toUpperCase(),
                  style: typography.paragraphNormal(
                    fontWeight: ArFontWeight.semiBold,
                    color: colorTokens.textHigh,
                  ),
                ),
                state.userDrives
                    .where((element) {
                      final isHidden = hideState is HiddingItems;

                      return element.isPrivate &&
                          (isHidden ? !element.isHidden : true);
                    })
                    .map(
                      (d) => DriveListTile(
                        hasAlert: state.drivesWithAlerts.contains(d.id),
                        drive: d,
                        onTap: () {
                          _closeDrawer(context);

                          context.read<DrivesCubit>().selectDrive(d.id);
                        },
                        isSelected: state.selectedDriveId == d.id,
                        isHidden: d.isHidden,
                      ),
                    )
                    .toList(),
              ),
            if (state.sharedDrives.isNotEmpty)
              ArDriveAccordionItem(
                isExpanded: true,
                Text(
                  appLocalizationsOf(context).sharedDrives.toUpperCase(),
                  style: typography.paragraphNormal(
                    fontWeight: ArFontWeight.semiBold,
                  ),
                ),

                /// Shared drives are always visible
                state.sharedDrives
                    .map(
                      (d) => DriveListTile(
                        hasAlert: state.drivesWithAlerts.contains(d.id),
                        drive: d,
                        onTap: () {
                          _closeDrawer(context);

                          context.read<DrivesCubit>().selectDrive(d.id);
                        },
                        isSelected: state.selectedDriveId == d.id,
                        isHidden: false,
                      ),
                    )
                    .toList(),
              ),
          ],
        );
      },
    );
  }

  void _closeDrawer(BuildContext context) {
    if (Scaffold.maybeOf(context) != null) {
      Scaffold.of(context).closeDrawer();
    }
  }
}
//

/// What the drive list shows before it knows what is in it.
///
/// The nav used to render nothing here, which is indistinguishable from a
/// wallet with no drives - and that is exactly what a returning user sees on a
/// device the app has not read yet. It says which it is now.

/// The way back to every drive, in the same place on every screen.
///
/// On the drives list it is the widest scope; inside a drive it is the way out.
/// One row either way, because to a reader they are the same thing - "show me
/// all of my drives" - and drawing them differently would be an implementation
/// detail leaking into the nav.
class _AllDrivesRow extends StatelessWidget {
  const _AllDrivesRow({
    required this.showLabel,
    required this.isOnDrivesList,
  });

  final bool showLabel;

  /// Whether the drives list is already the page, which decides whether this
  /// row narrows the table or navigates to it.
  final bool isOnDrivesList;

  @override
  Widget build(BuildContext context) {
    // `watch` only where the cubit is actually provided. The drives list page
    // provides it; every other shell does not, and reading it there throws
    // during build - which takes the entire sidebar down with it rather than
    // just this row.
    final drivesList =
        isOnDrivesList ? context.watch<DrivesListCubit?>() : null;
    final scopeIsAll = drivesList?.scope == DriveScope.all;

    return DriveNavRow(
      icon: DriveScopeRail.iconFor(DriveScope.all),
      label: appLocalizationsOf(context).allDrivesScope,
      showLabel: showLabel,
      isCurrent: scopeIsAll,
      onTap: () {
        if (Scaffold.maybeOf(context) != null) {
          Scaffold.of(context).closeDrawer();
        }

        final cubit = context.read<DrivesListCubit?>();

        if (isOnDrivesList && cubit != null) {
          cubit.showScope(DriveScope.all);
          return;
        }

        context.read<AppRouterDelegate>().showDrivesList();
      },
    );
  }
}
