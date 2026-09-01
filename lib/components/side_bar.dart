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
const Key sideBarDrivesListLinkKey = Key('sideBarDrivesListLink');

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
                    _buildDrivesListLink(isMobile: true),
                    const SizedBox(
                      height: 16,
                    ),
                    BlocBuilder<DrivesCubit, DrivesState>(
                      builder: (context, state) {
                        if (state is DrivesLoadSuccess &&
                            (state.userDrives.isNotEmpty ||
                                state.sharedDrives.isNotEmpty)) {
                          return Flexible(
                            child: _Accordion(
                              state: state,
                              isMobile: true,
                            ),
                          );
                        }
                        if (state is DrivesLoadInProgress) {
                          return const _DrivesStillLoading();
                        }
                        return const SizedBox();
                      },
                    ),
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
              height: constraints.maxHeight,
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: ArDriveTheme.of(context).themeData.colors.shadow,
                    width: 1,
                  ),
                ),
              ),
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
                            // The way back to the drives list, drawn in the
                            // gap that was already here rather than in room
                            // taken from the drive list below it. This column
                            // spent 56px on nothing between the New button
                            // and the drives; 16 + the entry's own 25 + 16 is
                            // 57 of it, so the list starts a pixel from where
                            // it started before. At a larger text scale the
                            // entry grows and the list moves down with it,
                            // exactly as everything else in this column does.
                            // `side_bar_drives_list_link_test.dart` measures
                            // it.
                            const SizedBox(
                              height: 16,
                            ),
                            _buildDrivesListLink(isMobile: false),
                            const SizedBox(
                              height: 16,
                            ),
                            _isExpanded
                                ? BlocBuilder<DrivesCubit, DrivesState>(
                                    builder: (context, state) {
                                      if (state is DrivesLoadSuccess &&
                                          (state.userDrives.isNotEmpty ||
                                              state.sharedDrives.isNotEmpty)) {
                                        return Flexible(
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                                left: 43.0),
                                            child: _Accordion(
                                              isMobile: false,
                                              state: state,
                                            ),
                                          ),
                                        );
                                      }
                                      if (state is DrivesLoadInProgress) {
                                        return const _DrivesStillLoading(
                                          leftPadding: 43,
                                        );
                                      }
                                      return const SizedBox();
                                    },
                                  )
                                : const SizedBox(),
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
  Widget _buildDrivesListLink({required bool isMobile}) {
    return _DrivesListLink(
      key: sideBarDrivesListLinkKey,
      // A collapsed desktop rail is 64px wide and shows no drive names either;
      // the icon carries it there, with the label in a tooltip.
      showLabel: isMobile || _isExpanded,
      // The left edge the accordion's own section headings sit on, so this
      // reads as their peer rather than as a row inside one of them. The
      // drawer has no such gutter and the collapsed rail centres its icon.
      leftPadding: isMobile || !_isExpanded ? 0 : 43,
      // The drive rows do this too: on a phone the nav is a drawer over the
      // page, and a drawer that stays open over what it just navigated to is
      // covering the answer.
      onTap: () {
        if (Scaffold.maybeOf(context) != null) {
          Scaffold.of(context).closeDrawer();
        }

        context.read<AppRouterDelegate>().showDrivesList();
      },
    );
  }

  Widget _buildLogo(bool isMobile) {
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
class _DrivesListLink extends StatelessWidget {
  const _DrivesListLink({
    super.key,
    required this.showLabel,
    required this.leftPadding,
    required this.onTap,
  });

  /// False on the collapsed desktop rail, which is 64px wide and shows no
  /// drive names either. The label becomes the tooltip there.
  final bool showLabel;

  final double leftPadding;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final label = appLocalizationsOf(context).yourDrives;

    return ArDriveClickArea(
      // The words the page itself is titled with. One destination named one
      // way, or the nav and the page it opens are two different places.
      tooltip: label,
      child: GestureDetector(
        onTap: onTap,
        // The whole row, not just the ink under the glyphs: a nav item that
        // only answers on its text is a smaller target than it looks.
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: EdgeInsets.only(
            left: leftPadding,
            right: 8,
            // The drive rows' own vertical padding, so this sits in the same
            // rhythm as the list it stands above.
            top: 2,
            bottom: 2,
          ),
          child: Row(
            mainAxisAlignment:
                showLabel ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              ArDriveIcons.bullertList(
                size: 16,
                color: colorTokens.textMid,
              ),
              if (showLabel) ...[
                const SizedBox(width: 8),
                // Wraps rather than ellipsizes, which is what the drive names
                // below it do (they are an Expanded Text with no maxLines). At
                // text scale 2.0 a single line clipped this to "Your D..."
                // while every drive under it stayed readable - one nav, two
                // rules, and the truncated one was the destination.
                Flexible(
                  child: Text(
                    label,
                    style: typography.paragraphNormal(
                      fontWeight: ArFontWeight.semiBold,
                      color: colorTokens.textMid,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

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
class _DrivesStillLoading extends StatelessWidget {
  const _DrivesStillLoading({this.leftPadding = 0});

  final double leftPadding;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Padding(
      padding: EdgeInsets.only(left: leftPadding, top: 8, bottom: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(colorTokens.textLow),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              appLocalizationsOf(context).loadingYourDrives,
              style: typography.paragraphSmall(color: colorTokens.textLow),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
