import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_bloc.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_event.dart';
import 'package:ardrive/components/migrate_private_drives_modal.dart';
import 'package:ardrive/components/profile_card.dart';
import 'package:ardrive/components/side_bar.dart';
import 'package:ardrive/components/sync_failure_test_panel.dart';
import 'package:ardrive/components/topbar/help_button.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/shared/blocs/private_drive_migration/private_drive_migration_bloc.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive/utils/size_constants.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/foundation.dart';
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
      logger.d('Wallet switch detected');
      context.read<ProfileCubit>().isCurrentProfileArConnect().then(
        (isCurrentProfileArConnect) {
          if (_showWalletSwitchDialog) {
            if (isCurrentProfileArConnect) {
              context.read<ArDriveAuth>().isUserLoggedIn().then((isLoggedIn) {
                context.read<ProfileCubit>().logoutIfWalletMismatch();
                if (isLoggedIn) {
                  logger.d('Wallet switch detected while logged in'
                      ' to ArConnect. Showing wallet switch dialog.');
                  showArDriveDialog(
                    context,
                    content: const WalletSwitchDialog(),
                  );
                }
              });
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
                      if (syncState is SyncInProgress || 
                          syncState is SyncCancelled || 
                          syncState is SyncCompleteWithErrors)
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
                                    
                                    if (syncState is SyncCancelled) {
                                      return Align(
                                        alignment: Alignment.center,
                                        child: Material(
                                          borderRadius: BorderRadius.circular(8),
                                          child: ArDriveStandardModalNew(
                                            title: appLocalizationsOf(context)
                                                .syncCancelled,
                                            content: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  appLocalizationsOf(context)
                                                      .syncProgressSaved,
                                                  style: typography.paragraphNormal(),
                                                ),
                                                const SizedBox(height: 12),
                                                Container(
                                                  padding: const EdgeInsets.all(12),
                                                  decoration: BoxDecoration(
                                                    color: ArDriveTheme.of(context)
                                                        .themeData
                                                        .colors
                                                        .themeWarningSubtle,
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(
                                                      color: ArDriveTheme.of(context)
                                                          .themeData
                                                          .colors
                                                          .themeWarningEmphasis,
                                                      width: 1,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        Icons.warning_amber_rounded,
                                                        size: 16,
                                                        color: ArDriveTheme.of(context)
                                                            .themeData
                                                            .colors
                                                            .themeWarningEmphasis,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          appLocalizationsOf(context)
                                                              .syncCancelledDetails(
                                                            syncState.drivesCompleted,
                                                            syncState.totalDrives,
                                                          ),
                                                          style: typography.paragraphSmall(
                                                            color: ArDriveTheme.of(context)
                                                                .themeData
                                                                .colors
                                                                .themeWarningEmphasis,
                                                            fontWeight: ArFontWeight.semiBold,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                            actions: [
                                              ModalAction(
                                                action: () {
                                                  context
                                                      .read<SyncCubit>()
                                                      .clearCancelledState();
                                                },
                                                title: appLocalizationsOf(context)
                                                    .ok,
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }
                                    
                                    if (syncState is SyncCompleteWithErrors) {
                                      return Align(
                                        alignment: Alignment.center,
                                        child: Material(
                                          borderRadius: BorderRadius.circular(8),
                                          child: ArDriveStandardModalNew(
                                            title: appLocalizationsOf(context)
                                                .syncCompleteWithErrors,
                                            content: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  appLocalizationsOf(context)
                                                      .syncPartialSuccessMessage(
                                                        syncState.failedDrives,
                                                        syncState.totalDrives,
                                                      ),
                                                  style: typography.paragraphNormal(),
                                                ),
                                                if (syncState.errorMessages.isNotEmpty) ...[
                                                  const SizedBox(height: 16),
                                                  Container(
                                                    padding: const EdgeInsets.all(12),
                                                    decoration: BoxDecoration(
                                                      color: ArDriveTheme.of(context)
                                                          .themeData
                                                          .colors
                                                          .themeBgSubtle,
                                                      borderRadius: BorderRadius.circular(8),
                                                      border: Border.all(
                                                        color: ArDriveTheme.of(context)
                                                            .themeData
                                                            .colors
                                                            .themeErrorDefault,
                                                        width: 1,
                                                      ),
                                                    ),
                                                    constraints: const BoxConstraints(
                                                      maxHeight: 200,
                                                    ),
                                                    child: SingleChildScrollView(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: syncState.errorMessages.entries
                                                            .map((entry) => Padding(
                                                                  padding: const EdgeInsets.only(bottom: 4),
                                                                  child: Text(
                                                                    '• ${entry.value}',
                                                                    style: typography.paragraphSmall(),
                                                                  ),
                                                                ))
                                                            .toList(),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            actions: [
                                              ModalAction(
                                                action: () {
                                                  context
                                                      .read<SyncCubit>()
                                                      .clearErrorState();
                                                },
                                                title: appLocalizationsOf(context)
                                                    .close,
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }
                                    
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
                                                Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (syncProgress.statusMessage != null)
                                                  Text(
                                                    syncProgress.statusMessage!,
                                                    style: typography.paragraphNormal(
                                                      fontWeight: ArFontWeight.semiBold,
                                                    ),
                                                  )
                                                else
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
                                              ],
                                            ),
                                          ),
                                          progressDescription:
                                              _syncStreamBuilder(
                                            builderWithData: (syncProgress) =>
                                                Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
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
                                                if (syncProgress.hasErrors) ...[
                                                  const SizedBox(height: 8),
                                                  Container(
                                                    padding: const EdgeInsets.all(8),
                                                    decoration: BoxDecoration(
                                                      color: ArDriveTheme.of(context)
                                                          .themeData
                                                          .colors
                                                          .themeWarningSubtle,
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          Icons.warning_amber_rounded,
                                                          size: 16,
                                                          color: ArDriveTheme.of(context)
                                                              .themeData
                                                              .colors
                                                              .themeWarningEmphasis,
                                                        ),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          appLocalizationsOf(context)
                                                              .syncErrorsDetected(
                                                                  syncProgress.failedQueries),
                                                          style: typography.paragraphSmall(
                                                            color: ArDriveTheme.of(context)
                                                                .themeData
                                                                .colors
                                                                .themeWarningEmphasis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          title: isCurrentProfileArConnect
                                              ? appLocalizationsOf(context)
                                                  .syncingPleaseRemainOnThisTab
                                              : appLocalizationsOf(context)
                                                  .syncingPleaseWait,
                                          actions: [
                                            ModalAction(
                                              action: () {
                                                context
                                                    .read<SyncCubit>()
                                                    .cancelSync();
                                              },
                                              title: appLocalizationsOf(context)
                                                  .cancelEmphasized,
                                            ),
                                          ],
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
                      // Add the sync failure test panel (only visible in debug mode)
                      if (kDebugMode) const SyncFailureTestPanel(),
                    ]);
                  },
                ),
              );
          return ScreenTypeLayout.builder(
            desktop: (context) {
              return buildPage(
                BlocBuilder<PrivateDriveMigrationBloc,
                    PrivateDriveMigrationState>(
                  builder: (context, state) {
                    return Column(
                      children: [
                        if (state is! PrivateDriveMigrationHidden)
                          _updatePrivateDrivesBanner(context, true),
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
            mobile: (context) => buildPage(
              BlocBuilder<PrivateDriveMigrationBloc,
                  PrivateDriveMigrationState>(
                builder: (context, state) {
                  return Column(
                    children: [
                      if (state is! PrivateDriveMigrationHidden)
                        _updatePrivateDrivesBanner(context, false),
                      Flexible(
                        child: Row(
                          children: [
                            Expanded(
                              child: Container(
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .backgroundColor,
                                child: widget.page,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      );

  Widget _updatePrivateDrivesBanner(BuildContext context, bool isDesktop) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      height: 45,
      width: double.maxFinite,
      color: colorTokens.buttonPrimaryDefault,
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          ArDriveIcons.privateDrive(
            color: colorTokens.textOnPrimary,
            size: 18,
          ),
          const SizedBox(width: 8),
          // move two pixels above
          Transform(
            transform: Matrix4.translationValues(0.0, -2.0, 0.0),
            child: isDesktop
                ? RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text:
                              'Please update your private drives to continue using them in the future: ',
                          style: typography.paragraphNormal(
                              fontWeight: ArFontWeight.semiBold,
                              color: colorTokens.textOnPrimary),
                        ),
                        TextSpan(
                          text: 'Update Now!',
                          recognizer: TapGestureRecognizer()
                            ..onTap = () {
                              showMigratePrivateDrivesModal(context);
                            },
                          style: typography
                              .paragraphNormal(
                                  fontWeight: ArFontWeight.semiBold,
                                  color: colorTokens.textOnPrimary)
                              .copyWith(
                                decoration: TextDecoration.underline,
                              ),
                        ),
                      ],
                    ),
                  )
                : GestureDetector(
                    onTap: () => showMigratePrivateDrivesModal(context),
                    child: Text(
                      'Please update your Private Drives',
                      style: typography
                          .paragraphNormal(
                            color: colorTokens.textOnPrimary,
                            fontWeight: ArFontWeight.semiBold,
                          )
                          .copyWith(decoration: TextDecoration.underline),
                    ),
                  ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

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
