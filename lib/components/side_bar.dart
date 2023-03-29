import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/blocs/sync/sync_cubit.dart';
import 'package:ardrive/components/app_drawer/app_drawer.dart';
import 'package:ardrive/components/new_button/new_button.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
        ));
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
          Padding(
            padding: const EdgeInsets.only(
              left: 24.0,
              right: 16,
              bottom: 16,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                child: ArDriveIcons.help(),
                onTap: () {},
              ),
            ),
          ),
          const SizedBox(
            height: 16,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 24.0),
            child: InkWell(
              onTap: () {
                arDriveAppKey.currentState?.changeTheme();
              },
              child: Text(
                ArDriveTheme.of(context).themeData.name == 'light'
                    ? 'DARK MODE'
                    : 'LIGHT MODE',
                style: ArDriveTypography.body.buttonNormalBold(),
              ),
            ),
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
        child: _isExpanded
            ? Column(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        const SizedBox(
                          height: 62,
                        ),
                        _buildLogo(),
                        const SizedBox(
                          height: 56,
                        ),
                        _buildDriveActionsButton(
                          context,
                          false,
                        ),
                        const SizedBox(
                          height: 56,
                        ),
                        BlocBuilder<DrivesCubit, DrivesState>(
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
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(
                    height: 16,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 51.0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: InkWell(
                        child: ArDriveIcons.help(),
                        onTap: () {},
                      ),
                    ),
                  ),
                  const SizedBox(
                    height: 16,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 43.0,
                      right: 24,
                      bottom: 24,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          children: [
                            InkWell(
                              onTap: () {
                                arDriveAppKey.currentState?.changeTheme();
                              },
                              child: Text(
                                ArDriveTheme.of(context).themeData.name ==
                                        'light'
                                    ? 'DARK MODE'
                                    : 'LIGHT MODE',
                                style:
                                    ArDriveTypography.body.buttonNormalBold(),
                              ),
                            ),
                            const AppVersionWidget(),
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
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ArDriveImage(
                    image: AssetImage(
                      Resources.images.brand.logo,
                    ),
                  ),
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.1,
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: ArDriveTheme.of(context)
                          .themeData
                          .colors
                          .themeAccentBrand,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(8.0),
                    child: _newButton(false, false),
                  ),
                  const SizedBox(
                    height: 32,
                  ),
                  const Spacer(),
                  InkWell(
                    child: ArDriveIcons.help(),
                    onTap: () {},
                  ),
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
                  const AppVersionWidget(),
                  const SizedBox(
                    height: 32,
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildLogo() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Image.asset(
        ArDriveTheme.of(context).themeData.name == 'light'
            ? Resources.images.brand.logoHorizontalNoSubtitleLight
            : Resources.images.brand.logoHorizontalNoSubtitleDark,
        height: 32,
        fit: BoxFit.contain,
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
            'Public Drives',
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
            'Private Drives',
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
            'Shared Drives',
            style: ArDriveTypography.body.buttonLargeBold(),
          ),
          state.sharedDrives
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

      return Column(
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
            return NewButton(
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
              child: InkWell(
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
            return NewButton(
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
    return Padding(
      padding: const EdgeInsets.only(left: 32.0, bottom: 8.0, top: 8.0),
      child: GestureDetector(
        onTap: onTap,
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
