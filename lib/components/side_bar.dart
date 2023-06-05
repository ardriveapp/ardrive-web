import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/blocs/sync/sync_cubit.dart';
import 'package:ardrive/components/new_button/new_button.dart';
import 'package:ardrive/components/theme_switcher.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/size_constants.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:responsive_builder/responsive_builder.dart';

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
      child: ScreenTypeLayout(
        mobile: _mobileView(),
        desktop: _desktopView(),
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
                    BlocBuilder<DrivesCubit, DrivesState>(
                      builder: (context, state) {
                        if (state is DrivesLoadSuccess &&
                            (state.userDrives.isNotEmpty ||
                                state.sharedDrives.isNotEmpty)) {
                          return Flexible(
                            child: _buildAccordion(
                              state,
                              true,
                            ),
                          );
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
              const Padding(
                padding: EdgeInsets.only(left: 16.0),
                child: HelpButton(),
              ),
              const SizedBox(
                height: 16,
              ),
              const Padding(
                padding: EdgeInsets.only(left: 16.0),
                child: ThemeSwitcher(),
              ),
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
    return ArDriveScrollBar(
      controller: _scrollController,
      child: SingleChildScrollView(
        controller: _scrollController,
        child: Container(
          height: MediaQuery.of(context).size.height,
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
                        const SizedBox(
                          height: 56,
                        ),
                        _isExpanded
                            ? BlocBuilder<DrivesCubit, DrivesState>(
                                builder: (context, state) {
                                  if (state is DrivesLoadSuccess &&
                                      (state.userDrives.isNotEmpty ||
                                          state.sharedDrives.isNotEmpty)) {
                                    return Flexible(
                                      child: Padding(
                                        padding:
                                            const EdgeInsets.only(left: 43.0),
                                        child: _buildAccordion(
                                          state,
                                          false,
                                        ),
                                      ),
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

  Widget _buildAccordion(DrivesLoadSuccess state, bool isMobile) {
    return ArDriveAccordion(
      contentPadding: isMobile ? const EdgeInsets.all(4) : null,
      key: ValueKey(state.userDrives.map((e) => e.name)),
      backgroundColor: ArDriveTheme.of(context).themeData.backgroundColor,
      children: [
        if (state.userDrives.isNotEmpty)
          ArDriveAccordionItem(
            isExpanded: true,
            Text(
              appLocalizationsOf(context).publicDrives,
              style: ArDriveTypography.body.buttonLargeBold().copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            state.userDrives
                .where((element) => element.isPublic)
                .map(
                  (d) => DriveListTile(
                    hasAlert: state.drivesWithAlerts.contains(d.id),
                    drive: d,
                    onTap: () {
                      if (state.selectedDriveId == d.id) {
                        // opens the root folder
                        context.read<DriveDetailCubit>().openFolder(path: '');
                        return;
                      }
                      context.read<DrivesCubit>().selectDrive(d.id);
                    },
                    isSelected: state.selectedDriveId == d.id,
                  ),
                )
                .toList(),
          ),
        if (state.userDrives.isNotEmpty)
          ArDriveAccordionItem(
            isExpanded: true,
            Text(
              appLocalizationsOf(context).privateDrives,
              style: ArDriveTypography.body
                  .buttonLargeBold()
                  .copyWith(fontWeight: FontWeight.w700),
            ),
            state.userDrives
                .where((element) => element.isPrivate)
                .map(
                  (d) => DriveListTile(
                    hasAlert: state.drivesWithAlerts.contains(d.id),
                    drive: d,
                    onTap: () {
                      context.read<DrivesCubit>().selectDrive(d.id);
                    },
                    isSelected: state.selectedDriveId == d.id,
                  ),
                )
                .toList(),
          ),
        if (state.sharedDrives.isNotEmpty)
          ArDriveAccordionItem(
            isExpanded: true,
            Text(
              appLocalizationsOf(context).sharedDrives,
              style: ArDriveTypography.body
                  .buttonLargeBold()
                  .copyWith(fontWeight: FontWeight.w700),
            ),
            state.sharedDrives
                .map(
                  (d) => DriveListTile(
                    hasAlert: state.drivesWithAlerts.contains(d.id),
                    drive: d,
                    onTap: () {
                      context.read<DrivesCubit>().selectDrive(d.id);
                    },
                    isSelected: state.selectedDriveId == d.id,
                  ),
                )
                .toList(),
          ),
      ],
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
                const Align(
                  alignment: Alignment.centerLeft,
                  child: HelpButton(),
                ),
                const SizedBox(
                  height: 24,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        ThemeSwitcher(),
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
              const HelpButton(),
              const SizedBox(
                height: 24,
              ),
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

  Widget _buildSyncButton() {
    return BlocBuilder<SyncCubit, SyncState>(
      builder: (context, syncState) {
        return PopupMenuButton(
          color: kDarkSurfaceColor,
          tooltip: appLocalizationsOf(context).resync,
          onSelected: ((value) {
            context
                .read<SyncCubit>()
                .startSync(syncDeep: value == SyncType.deep);
          }),
          itemBuilder: (context) {
            return [
              PopupMenuItem<SyncType>(
                value: SyncType.normal,
                child: Tooltip(
                  message: appLocalizationsOf(context).resyncTooltip,
                  child: ListTile(
                    leading: const Icon(Icons.sync),
                    title: Text(appLocalizationsOf(context).resync),
                  ),
                ),
              ),
              PopupMenuItem<SyncType>(
                value: SyncType.deep,
                child: Tooltip(
                  message: appLocalizationsOf(context).deepResyncTooltip,
                  child: ListTile(
                    leading: const Icon(Icons.cloud_sync),
                    title: Text(appLocalizationsOf(context).deepResync),
                  ),
                ),
              ),
            ];
          },
          icon: const Icon(Icons.sync),
          position: PopupMenuPosition.under,
        );
      },
    );
  }

  Widget _buildDriveActionsButton(
    BuildContext context,
    bool isMobile,
  ) {
    final minimumWalletBalance = BigInt.from(10000000);

    final profileState = context.watch<ProfileCubit>().state;

    if (profileState is ProfileLoggedIn) {
      final profile = profileState;
      final notEnoughARInWallet = !profile.hasMinimumBalanceForUpload(
        minimumWalletBalance: minimumWalletBalance,
      );

      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Column(
          children: [
            Align(
              alignment: Alignment.center,
              child: _newButton(_isExpanded, isMobile),
            ),
            if (notEnoughARInWallet && _isExpanded)
              ArDriveButton(
                style: ArDriveButtonStyle.tertiary,
                onPressed: () => openUrl(url: Resources.arHelpLink),
                text: appLocalizationsOf(context).howDoIGetAR,
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

class DriveListTile extends StatelessWidget {
  final Drive drive;
  final bool hasAlert;
  final bool isSelected;
  final VoidCallback onTap;

  const DriveListTile({
    Key? key,
    required this.drive,
    required this.isSelected,
    required this.onTap,
    this.hasAlert = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: key,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(
          left: 32.0,
          right: 8.0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          mainAxisSize: MainAxisSize.max,
          children: [
            Flexible(
              child: HoverWidget(
                hoverScale: 1,
                child: Text(
                  drive.name,
                  style: isSelected
                      ? ArDriveTypography.body
                          .buttonNormalBold(
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeFgDefault,
                          )
                          .copyWith(fontWeight: FontWeight.w700)
                      : ArDriveTypography.body.buttonNormalRegular(
                          color: ArDriveTheme.of(context)
                              .themeData
                              .colors
                              .themeAccentDisabled,
                        ),
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

class HelpButton extends StatelessWidget {
  const HelpButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ArDriveIconButton(
      tooltip: appLocalizationsOf(context).help,
      icon: ArDriveIcons.question(),
      onPressed: () {
        openUrl(url: Resources.helpLink);
      },
    );
  }
}

class AppVersionWidget extends StatelessWidget {
  const AppVersionWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: PackageInfo.fromPlatform(),
      builder: (BuildContext context, AsyncSnapshot<PackageInfo> snapshot) {
        final info = snapshot.data;
        if (info == null) {
          return const SizedBox(
            height: 32,
            width: 32,
          );
        }
        final literalVersion =
            kIsWeb ? info.version : '${info.version}+${info.buildNumber}';
        return Text(
          appLocalizationsOf(context).appVersion(literalVersion),
          style: ArDriveTypography.body.buttonNormalRegular(
            color: Colors.grey,
          ),
          textAlign: TextAlign.center,
        );
      },
    );
  }
}
