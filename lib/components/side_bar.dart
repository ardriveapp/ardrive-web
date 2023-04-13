import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/blocs/sync/sync_cubit.dart';
import 'package:ardrive/components/new_button/new_button.dart';
import 'package:ardrive/components/theme_switcher.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/open_url.dart';
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
    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.75,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: [
                const SizedBox(
                  height: 64,
                ),
                _buildLogo(),
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
                            state.sharedDrives.isEmpty)) {
                      return Flexible(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 16.0),
                          child: _buildAccordion(
                            state,
                          ),
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
          const SizedBox(
            height: 16,
          ),
          const Padding(
            padding: EdgeInsets.only(left: 16.0),
            child: ThemeSwitcher(),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 16.0),
            child: AppVersionWidget(),
          ),
          const SizedBox(
            height: 32,
          ),
        ],
      ),
    );
  }

  Widget _desktopView() {
    return AnimatedSize(
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
                    _buildLogo(),
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
                                      state.sharedDrives.isEmpty)) {
                                return Flexible(
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 43.0),
                                    child: _buildAccordion(
                                      state,
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
          )),
    );
  }

  Widget _buildLogo() {
    return SizedBox(
      height: 64,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        child: _isExpanded
            ? Padding(
                padding: const EdgeInsets.all(16.0),
                child: Image.asset(
                  ArDriveTheme.of(context).themeData.name == 'light'
                      ? Resources.images.brand.logoHorizontalNoSubtitleLight
                      : Resources.images.brand.logoHorizontalNoSubtitleDark,
                  height: 32,
                  fit: BoxFit.contain,
                ),
              )
            : ArDriveImage(
                width: 62,
                height: 62,
                image: AssetImage(
                  Resources.images.brand.logo,
                ),
              ),
      ),
    );
  }

  Widget _buildAccordion(DrivesLoadSuccess state) {
    return ArDriveAccordion(
      backgroundColor: ArDriveTheme.of(context).themeData.backgroundColor,
      children: [
        ArDriveAccordionItem(
          isExpanded: true,
          Text(
            appLocalizationsOf(context).publicDrives,
            style: ArDriveTypography.body.buttonLargeBold(),
          ),
          state.userDrives
              .where((element) => element.privacy == 'public')
              .map(
                (d) => DriveListTile(
                  drive: d,
                  onTap: () {
                    context.read<DrivesCubit>().selectDrive(d.id);
                  },
                  isSelected: state.selectedDriveId == d.id,
                ),
              )
              .toList(),
        ),
        ArDriveAccordionItem(
          isExpanded: true,
          Text(
            appLocalizationsOf(context).privateDrives,
            style: ArDriveTypography.body.buttonLargeBold(),
          ),
          state.userDrives
              .where((element) => element.privacy == 'private')
              .map(
                (d) => DriveListTile(
                  drive: d,
                  onTap: () {
                    context.read<DrivesCubit>().selectDrive(d.id);
                  },
                  isSelected: state.selectedDriveId == d.id,
                ),
              )
              .toList(),
        ),
        ArDriveAccordionItem(
          isExpanded: true,
          Text(
            appLocalizationsOf(context).sharedDrives,
            style: ArDriveTypography.body.buttonLargeBold(),
          ),
          state.sharedDrives
              .map(
                (d) => DriveListTile(
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: HelpButton(),
                    ),
                    SizedBox(
                      height: 8,
                    ),
                    ThemeSwitcher(),
                    SizedBox(
                      height: 8,
                    ),
                    AppVersionWidget(),
                  ],
                ),
                InkWell(
                  child: ArDriveIcons.arrowBackFilled(),
                  onTap: () {
                    setState(() {
                      _isExpanded = !_isExpanded;
                    });
                  },
                ),
              ],
            ),
          )
        : Column(
            children: [
              const HelpButton(),
              const SizedBox(
                height: 32,
              ),
              InkWell(
                child: ArDriveIcons.arrowForwardFilled(),
                onTap: () {
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

    if (profileState.runtimeType == ProfileLoggedIn) {
      final profile = profileState as ProfileLoggedIn;
      final notEnoughARInWallet = !profile.hasMinimumBalanceForUpload(
        minimumWalletBalance: minimumWalletBalance,
      );

      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _isExpanded
            ? Column(
                children: [
                  Align(
                    alignment: Alignment.center,
                    child: _newButton(_isExpanded, isMobile),
                  ),
                  if (notEnoughARInWallet) ...{
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        appLocalizationsOf(context).insufficientARWarning,
                        style: ArDriveTypography.body.captionRegular(
                          color: ArDriveTheme.of(context)
                              .themeData
                              .colors
                              .themeAccentDisabled,
                        ),
                      ),
                    ),
                    ArDriveButton(
                      style: ArDriveButtonStyle.primary,
                      onPressed: () => openUrl(url: Resources.arHelpLink),
                      text: appLocalizationsOf(context).howDoIGetAR,
                    ),
                  }
                ],
              )
            : Container(
                decoration: BoxDecoration(
                  color: ArDriveTheme.of(context)
                      .themeData
                      .colors
                      .themeAccentBrand,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 10),
                child: _newButton(false, false),
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
    return BlocBuilder<DriveDetailCubit, DriveDetailState>(
      builder: (context, state) {
        if (state is DriveDetailLoadSuccess) {
          if (isExpanded) {
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
                drive: state.currentDrive,
                driveDetailState: state,
                currentFolder: state.folderInView,
                child: Container(
                  width: 128,
                  height: 40,
                  decoration: BoxDecoration(
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeAccentBrand,
                    borderRadius: const BorderRadius.all(
                      Radius.circular(8),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      appLocalizationsOf(context).newString,
                      style: ArDriveTypography.headline.headline5Bold(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            );
          } else {
            return ArDriveClickArea(
              tooltip: appLocalizationsOf(context).showMenu,
              child: NewButton(
                anchor: const Aligned(
                  follower: Alignment.topLeft,
                  target: Alignment.topRight,
                ),
                drive: state.currentDrive,
                driveDetailState: state,
                currentFolder: state.folderInView,
                child: ArDriveIcons.plus(
                  color: Colors.white,
                ),
              ),
            );
          }
        }

        return const SizedBox(
          height: 40,
        );
      },
    );
  }
}

class DriveListTile extends StatelessWidget {
  final Drive drive;
  final bool isSelected;
  final VoidCallback onTap;

  const DriveListTile({
    Key? key,
    required this.drive,
    required this.isSelected,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 32.0, bottom: 8.0, top: 8.0),
        child: Text(
          drive.name,
          style: ArDriveTypography.body.buttonNormalBold(
            color: isSelected
                ? ArDriveTheme.of(context).themeData.colors.themeFgDefault
                : ArDriveTheme.of(context).themeData.colors.themeAccentDisabled,
          ),
        ),
      ),
    );
  }
}

class HelpButton extends StatelessWidget {
  const HelpButton({super.key});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      child: ArDriveIcons.help(),
      onTap: () {
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
