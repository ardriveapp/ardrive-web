import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_bloc.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_event.dart';
import 'package:ardrive/components/profile_card.dart';
import 'package:ardrive/components/side_bar.dart';
import 'package:ardrive/components/topbar/help_button.dart';
import 'package:ardrive/drive_explorer/multi_thumbnail_creation/multi_thumbnail_creation_warn_modal.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/shared/blocs/banner/app_banner_bloc.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive/utils/size_constants.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

import 'blocs/blocs.dart';
import 'components/app_top_bar.dart';
import 'components/components.dart';
import 'components/progress_bar.dart';
import 'components/wallet_switch_dialog.dart';
import 'utils/app_localizations_wrapper.dart';

class AppShell extends StatefulWidget {
  final Widget page;

  const AppShell({
    super.key,
    required this.page,
  });

  @override
  AppShellState createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  bool _showProfileOverlay = false;
  bool _showWalletSwitchDialog = true;

  @override
  void initState() {
    onArConnectWalletSwitch(() {
      context.read<ProfileCubit>().isCurrentProfileArConnect().then(
        (isCurrentProfileArConnect) {
          if (_showWalletSwitchDialog) {
            if (isCurrentProfileArConnect) {
              showDialog(
                context: context,
                builder: (context) => const WalletSwitchDialog(),
              );
            } else {
              logger.d('Wallet switch detected while not logged in'
                  ' to ArConnect. Ignoring.');
            }
          }
          // Used to prevent the dialog being shown multiple times.
          _showWalletSwitchDialog = false;
        },
      );
    });

    super.initState();
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<DrivesCubit, DrivesState>(
        builder: (context, drivesState) {
          Widget buildPage(scaffold) => Material(
                child: BlocConsumer<SyncCubit, SyncState>(
                  listener: (context, syncState) async {
                    if (drivesState is DrivesLoadSuccess) {
                      if (syncState is! SyncInProgress) {
                        final promptToSnapshotBloc =
                            context.read<PromptToSnapshotBloc>();

                        promptToSnapshotBloc.add(SelectedDrive(
                          driveId: drivesState.selectedDriveId,
                        ));
                      }
                    }
                  },
                  builder: (context, syncState) {
                    return Stack(children: [
                      scaffold,
                      if (syncState is SyncInProgress)
                        Stack(
                          children: [
                            SizedBox.expand(
                              child: Container(
                                color: Colors.black.withOpacity(0.5),
                              ),
                            ),
                            BlocBuilder<ProfileCubit, ProfileState>(
                              builder: (context, state) {
                                final typography =
                                    ArDriveTypographyNew.of(context);
                                return FutureBuilder(
                                  future: context
                                      .read<ProfileCubit>()
                                      .isCurrentProfileArConnect(),
                                  builder: (BuildContext context,
                                      AsyncSnapshot snapshot) {
                                    final isCurrentProfileArConnect =
                                        snapshot.data == true;
                                    return Align(
                                      alignment: Alignment.center,
                                      child: Material(
                                        borderRadius: BorderRadius.circular(8),
                                        child: ProgressDialog(
                                          useNewArDriveUI: true,
                                          progressBar: ProgressBar(
                                            percentage: context
                                                .read<SyncCubit>()
                                                .syncProgressController
                                                .stream,
                                          ),
                                          percentageDetails: _syncStreamBuilder(
                                            builderWithData: (syncProgress) =>
                                                Text(
                                              appLocalizationsOf(context)
                                                  .syncProgressPercentage(
                                                (syncProgress.progress * 100)
                                                    .roundToDouble()
                                                    .toString(),
                                              ),
                                              style: typography.paragraphNormal(
                                                fontWeight: ArFontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          progressDescription:
                                              _syncStreamBuilder(
                                            builderWithData: (syncProgress) =>
                                                Text(
                                              syncProgress.drivesCount == 0
                                                  ? ''
                                                  : syncProgress.drivesCount > 1
                                                      ? appLocalizationsOf(
                                                              context)
                                                          .driveSyncedOfDrivesCount(
                                                              syncProgress
                                                                  .drivesSynced,
                                                              syncProgress
                                                                  .drivesCount)
                                                      : appLocalizationsOf(
                                                              context)
                                                          .syncingOnlyOneDrive,
                                              style: typography.paragraphNormal(
                                                fontWeight: ArFontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          title: isCurrentProfileArConnect
                                              ? appLocalizationsOf(context)
                                                  .syncingPleaseRemainOnThisTab
                                              : appLocalizationsOf(context)
                                                  .syncingPleaseWait,
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                            if (context.read<ConfigService>().flavor !=
                                Flavor.production)
                              Positioned(
                                bottom: 0,
                                right: 20,
                                child: Text(
                                  'Using gateway: ${context.read<ConfigService>().config.defaultArweaveGatewayUrl}',
                                  style: ArDriveTypographyNew.of(context)
                                      .paragraphLarge(
                                    fontWeight: ArFontWeight.semiBold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                    ]);
                  },
                ),
              );
          return ScreenTypeLayout.builder(
            desktop: (context) {
              final colorTokens =
                  ArDriveTheme.of(context).themeData.colorTokens;
              final typography = ArDriveTypographyNew.of(context);

              return buildPage(
                BlocBuilder<AppBannerBloc, AppBannerState>(
                  builder: (context, state) {
                    return Column(
                      children: [
                        if (state is AppBannerVisible)
                          Container(
                            height: 45,
                            width: double.maxFinite,
                            color: colorTokens.buttonPrimaryDefault,
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Spacer(),
                                ArDriveIcons.asc(
                                  color: colorTokens.textOnPrimary,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                // move two pixels above
                                Transform(
                                  transform:
                                      Matrix4.translationValues(0.0, -2.0, 0.0),
                                  child: RichText(
                                    text: TextSpan(
                                      children: [
                                        TextSpan(
                                          text:
                                              'ArDrive now supports thumbnails! You can ',
                                          style: typography.paragraphNormal(
                                              fontWeight: ArFontWeight.semiBold,
                                              color: colorTokens.textOnPrimary),
                                        ),
                                        TextSpan(
                                          text: 'add them now!',
                                          recognizer: TapGestureRecognizer()
                                            ..onTap = () {
                                              showArDriveDialog(context,
                                                  content:
                                                      const MultiThumbnailCreationWarningModal());
                                            },
                                          style: typography
                                              .paragraphNormal(
                                                  fontWeight:
                                                      ArFontWeight.semiBold,
                                                  color:
                                                      colorTokens.textOnPrimary)
                                              .copyWith(
                                                decoration:
                                                    TextDecoration.underline,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: GestureDetector(
                                    onTap: () {
                                      context
                                          .read<AppBannerBloc>()
                                          .add(const AppBannerCloseEvent());
                                    },
                                    child: ArDriveIcons.x(
                                      color: colorTokens.textOnPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Flexible(
                          child: Row(
                            children: [
                              const AppSideBar(),
                              Container(
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .backgroundColor,
                                width: 16,
                              ),
                              Expanded(
                                child: Scaffold(
                                  backgroundColor: ArDriveTheme.of(context)
                                      .themeData
                                      .backgroundColor,
                                  body: widget.page,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              );
            },
            mobile: (context) => buildPage(widget.page),
          );
        },
      );

  Widget _syncStreamBuilder({
    required Widget Function(SyncProgress s) builderWithData,
  }) =>
      StreamBuilder<SyncProgress>(
        stream: context.read<SyncCubit>().syncProgressController.stream,
        builder: (context, snapshot) =>
            snapshot.hasData ? builderWithData(snapshot.data!) : Container(),
      );

  void toggleProfileOverlay() =>
      setState(() => _showProfileOverlay = !_showProfileOverlay);
}

// TODO: add the gift icon
class MobileAppBar extends StatelessWidget implements PreferredSizeWidget {
  const MobileAppBar({
    super.key,
    this.leading,
    this.showDrawerButton = true,
  });

  final Widget? leading;
  final bool showDrawerButton;

  @override
  Size get preferredSize =>
      const Size.fromHeight(80); // Set the height of the appbar

  @override
  Widget build(BuildContext context) {
    final isLightMode = ArDriveTheme.of(context).themeData.name == 'light';
    return SafeArea(
      child: Container(
        height: 80,
        color: ArDriveTheme.of(context).themeData.tableTheme.cellColor,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 7.0),
              child: leading ??
                  (showDrawerButton
                      ? ArDriveIconButton(
                          icon: ArDriveIcons.menu(
                            size: defaultIconSize,
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeFgDefault,
                          ),
                          onPressed: () => Scaffold.of(context).openDrawer(),
                        )
                      : Container()),
            ),
            if (!showDrawerButton)
              Padding(
                padding: const EdgeInsets.only(
                  left: 24.0,
                ),
                child: ArDriveImage(
                  image: AssetImage(
                    isLightMode
                        ? Resources.images.brand.blackLogo1
                        : Resources.images.brand.whiteLogo1,
                  ),
                  width: 128,
                  height: 28,
                ),
              ),
            const Spacer(),
            const GlobalHideToggleButton(),
            const SizedBox(width: 8),
            const SyncButton(),
            const SizedBox(width: 8),
            if (AppPlatform.isMobileWeb()) ...[
              const HelpButtonTopBar(),
            ],
            const SizedBox(
              width: 24,
            ),
            const Padding(
              padding: EdgeInsets.only(right: 12.0),
              child: ProfileCard(),
            ),
          ],
        ),
      ),
    );
  }
}
