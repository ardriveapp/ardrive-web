import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/app_drawer/drive_list_tile.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/services/analytics/ardrive_analytics.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/launch_inferno_rules.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => ListTileTheme(
        style: ListTileStyle.drawer,
        textColor: kOnDarkSurfaceMediumEmphasis,
        iconColor: kOnDarkSurfaceMediumEmphasis,
        selectedColor: kOnDarkSurfaceHighEmphasis,
        selectedTileColor: onDarkSurfaceSelectedColor,
        child: BlocBuilder<DrivesCubit, DrivesState>(
          builder: (context, state) => Drawer(
            elevation: 1,
            child: Container(
              color: kDarkSurfaceColor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        const SizedBox(
                          height: 32,
                        ),
                        _buildLogo(),
                        const SizedBox(
                          height: 32,
                        ),
                        BlocBuilder<ProfileCubit, ProfileState>(
                            builder: (context, profileState) {
                          return _buildDriveActionsButton(
                              context, state, profileState);
                        }),
                        if (state is DrivesLoadSuccess)
                          Expanded(
                            child: Scrollbar(
                              child: ListView(
                                padding: const EdgeInsets.all(21),
                                key: const PageStorageKey<String>(
                                  'driveScrollView',
                                ),
                                children: [
                                  if (state.userDrives.isNotEmpty ||
                                      state.sharedDrives.isEmpty) ...{
                                    ListTile(
                                      dense: true,
                                      title: Text(
                                        appLocalizationsOf(context)
                                            .personalDrivesEmphasized,
                                        textAlign: TextAlign.start,
                                        style: Theme.of(context)
                                            .textTheme
                                            .caption!
                                            .copyWith(
                                                color: ListTileTheme.of(context)
                                                    .textColor),
                                      ),
                                      trailing: _buildSyncButton(),
                                    ),
                                    ...state.userDrives.map(
                                      (d) => DriveListTile(
                                        drive: d,
                                        selected: state.selectedDriveId == d.id,
                                        onPressed: () {
                                          context
                                              .read<ArDriveAnalytics>()
                                              .trackScreenEvent(
                                                screenName: "mainMenu",
                                                eventName: "driveSelected",
                                              );
                                          context
                                              .read<DrivesCubit>()
                                              .selectDrive(d.id);
                                        },
                                        hasAlert: state.drivesWithAlerts
                                            .contains(d.id),
                                      ),
                                    ),
                                  },
                                  if (state.sharedDrives.isNotEmpty) ...{
                                    ListTile(
                                      dense: true,
                                      title: Text(
                                        appLocalizationsOf(context)
                                            .sharedDrivesEmphasized,
                                        textAlign: TextAlign.start,
                                        style: Theme.of(context)
                                            .textTheme
                                            .caption!
                                            .copyWith(
                                                color: ListTileTheme.of(context)
                                                    .textColor),
                                      ),
                                      trailing: state.userDrives.isEmpty
                                          ? _buildSyncButton()
                                          : null,
                                    ),
                                    ...state.sharedDrives.map(
                                      (d) => DriveListTile(
                                        drive: d,
                                        selected: state.selectedDriveId == d.id,
                                        onPressed: () => context
                                            .read<DrivesCubit>()
                                            .selectDrive(d.id),
                                      ),
                                    ),
                                  }
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 21 + 8,
                      vertical: 21,
                    ),
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: FloatingActionButton(
                                elevation: 0,
                                tooltip: appLocalizationsOf(context).help,
                                onPressed: () {
                                  context
                                      .read<ArDriveAnalytics>()
                                      .trackScreenEvent(
                                          screenName: "mainMenu",
                                          eventName: "helpButton");
                                  launch(Resources.helpLink);
                                },
                                child: const Icon(Icons.help_outline),
                              ),
                            ),
                            FutureBuilder(
                              future: PackageInfo.fromPlatform(),
                              builder: (BuildContext context,
                                  AsyncSnapshot<PackageInfo> snapshot) {
                                if (snapshot.hasData) {
                                  return Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Text(
                                      appLocalizationsOf(context)
                                          .appVersion(snapshot.data!.version),
                                      style: Theme.of(context)
                                          .textTheme
                                          .caption!
                                          .copyWith(color: Colors.grey),
                                    ),
                                  );
                                } else {
                                  return const SizedBox(
                                    height: 32,
                                    width: 32,
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.only(
                                  top: 8.0,
                                  bottom: 8.0,
                                ),
                              ),
                              onPressed: () {
                                context
                                    .read<ArDriveAnalytics>()
                                    .trackScreenEvent(
                                        screenName: "mainMenu",
                                        eventName: "infernoButton");
                                launchInfernoRulesURL(
                                    appLocalizationsOf(context).localeName);
                              },
                              child: Tooltip(
                                message: appLocalizationsOf(context)
                                    .infernoIsInFullSwing,
                                child: Column(
                                  children: [
                                    Image.asset(
                                      Resources.images.inferno.fire,
                                      height: 50.0,
                                      width: 50.0,
                                      fit: BoxFit.contain,
                                    ),
                                    SizedBox(
                                      height: 32,
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          top: 16.0,
                                        ),
                                        child: Text(
                                          'Inferno',
                                          style: Theme.of(context)
                                              .textTheme
                                              .caption!
                                              .copyWith(color: Colors.grey),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  Widget _buildLogo() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Image.asset(
        Resources.images.brand.logoHorizontalNoSubtitleDark,
        height: 32,
        fit: BoxFit.contain,
      ),
    );
  }

  Widget _buildDriveActionsButton(BuildContext context, DrivesState drivesState,
      ProfileState profileState) {
    final theme = Theme.of(context);
    final minimumWalletBalance = BigInt.from(10000000);

    if (profileState.runtimeType == ProfileLoggedIn) {
      final profile = profileState as ProfileLoggedIn;
      final hasMinBalance = profile.walletBalance >= minimumWalletBalance;
      return Column(
        children: [
          ListTileTheme(
            textColor: theme.textTheme.bodyText1!.color,
            iconColor: theme.iconTheme.color,
            child: Align(
              alignment: Alignment.center,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                child: BlocBuilder<DriveDetailCubit, DriveDetailState>(
                  builder: (context, state) => PopupMenuButton<Function>(
                    onSelected: (callback) => callback(context),
                    itemBuilder: (context) => [
                      if (state is DriveDetailLoadSuccess) ...{
                        _buildNewFolderItem(context, state, hasMinBalance),
                        const PopupMenuDivider(key: Key('divider-1')),
                        _buildUploadFileItem(context, state, hasMinBalance),
                        _buildUploadFolderItem(context, state, hasMinBalance),
                        const PopupMenuDivider(key: Key('divider-2')),
                      },
                      if (drivesState is DrivesLoadSuccess) ...{
                        _buildCreateDrive(context, drivesState, hasMinBalance),
                        _buildAttachDrive(context)
                      },
                      if (state is DriveDetailLoadSuccess &&
                          state.currentDrive.privacy == 'public') ...{
                        _buildCreateManifestItem(context, state, hasMinBalance)
                      },
                    ],
                    child: _buildNewButton(context),
                  ),
                ),
              ),
            ),
          ),
          if (!hasMinBalance) ...{
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                appLocalizationsOf(context).insufficientARWarning,
                style: Theme.of(context)
                    .textTheme
                    .caption!
                    .copyWith(color: Colors.grey),
              ),
            ),
            TextButton(
              onPressed: () {
                context.read<ArDriveAnalytics>().trackScreenEvent(
                    screenName: "mainMenu", eventName: "arHelpButton");
                launch(Resources.arHelpLink);
              },
              child: Text(
                appLocalizationsOf(context).howDoIGetAR,
                style: const TextStyle(
                  color: Colors.grey,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          }
        ],
      );
    } else {
      return ListTileTheme(
        textColor: theme.textTheme.bodyText1!.color,
        iconColor: theme.iconTheme.color,
        child: Align(
          alignment: Alignment.center,
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
              child: PopupMenuButton<Function>(
                  onSelected: (callback) => callback(context),
                  itemBuilder: (context) => [
                        if (drivesState is DrivesLoadSuccess) ...{
                          PopupMenuItem(
                            value: (context) => attachDrive(context: context),
                            child: ListTile(
                              title:
                                  Text(appLocalizationsOf(context).attachDrive),
                            ),
                          ),
                        }
                      ],
                  child: _buildNewButton(context))),
        ),
      );
    }
  }

  PopupMenuEntry<Function> _buildNewFolderItem(
      context, DriveDetailLoadSuccess state, bool hasMinBalance) {
    return _buildMenuItemTile(
      context: context,
      isEnabled: state.hasWritePermissions && hasMinBalance,
      itemTitle: appLocalizationsOf(context).newFolder,
      message: state.hasWritePermissions && !hasMinBalance
          ? appLocalizationsOf(context).insufficientFundsForCreateAFolder
          : null,
      value: (context) => promptToCreateFolder(
        context,
        driveId: state.currentDrive.id,
        parentFolderId: state.folderInView.folder.id,
      ),
    );
  }

  PopupMenuEntry<Function> _buildUploadFileItem(
      context, DriveDetailLoadSuccess state, bool hasMinBalance) {
    return _buildMenuItemTile(
      context: context,
      isEnabled: state.hasWritePermissions && hasMinBalance,
      message: state.hasWritePermissions && !hasMinBalance
          ? appLocalizationsOf(context).insufficientFundsForUploadFiles
          : null,
      itemTitle: appLocalizationsOf(context).uploadFiles,
      value: (context) => promptToUpload(
        context,
        driveId: state.currentDrive.id,
        folderId: state.folderInView.folder.id,
        isFolderUpload: false,
      ),
    );
  }

  PopupMenuEntry<Function> _buildUploadFolderItem(
      context, DriveDetailLoadSuccess state, bool hasMinBalance) {
    return _buildMenuItemTile(
      context: context,
      isEnabled: state.hasWritePermissions && hasMinBalance,
      itemTitle: appLocalizationsOf(context).uploadFolder,
      message: state.hasWritePermissions && !hasMinBalance
          ? appLocalizationsOf(context).insufficientFundsForUploadFolders
          : null,
      value: (context) => promptToUpload(
        context,
        driveId: state.currentDrive.id,
        folderId: state.folderInView.folder.id,
        isFolderUpload: true,
      ),
    );
  }

  PopupMenuEntry<Function> _buildAttachDrive(BuildContext context) {
    return PopupMenuItem(
      value: (context) => attachDrive(context: context),
      child: ListTile(
        title: Text(appLocalizationsOf(context).attachDrive),
      ),
    );
  }

  PopupMenuEntry<Function> _buildCreateDrive(
      BuildContext context, DrivesLoadSuccess drivesState, bool hasMinBalance) {
    return _buildMenuItemTile(
      context: context,
      isEnabled: drivesState.canCreateNewDrive && hasMinBalance,
      itemTitle: appLocalizationsOf(context).newDrive,
      message: hasMinBalance
          ? null
          : appLocalizationsOf(context).insufficientFundsForCreateADrive,
      value: (context) => promptToCreateDrive(context),
    );
  }

  Widget _buildNewButton(BuildContext context) {
    return SizedBox(
      width: 164,
      height: 36,
      child: FloatingActionButton.extended(
        onPressed: null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        label: Text(
          appLocalizationsOf(context).newStringEmphasized,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  PopupMenuEntry<Function> _buildCreateManifestItem(
      BuildContext context, DriveDetailLoadSuccess state, bool hasMinBalance) {
    return _buildMenuItemTile(
      context: context,
      isEnabled: !state.driveIsEmpty && hasMinBalance,
      itemTitle: appLocalizationsOf(context).createManifest,
      message: !state.driveIsEmpty && !hasMinBalance
          ? appLocalizationsOf(context).insufficientFundsForCreateAManifest
          : null,
      value: (context) =>
          promptToCreateManifest(context, drive: state.currentDrive),
    );
  }

  PopupMenuEntry<Function> _buildMenuItemTile(
      {required bool isEnabled,
      Future<void> Function(dynamic)? value,
      String? message,
      required String itemTitle,
      required BuildContext context}) {
    return PopupMenuItem(
      value: value,
      enabled: isEnabled,
      child: Tooltip(
        message: message ?? '',
        child: ListTile(
          textColor:
              isEnabled ? ListTileTheme.of(context).textColor : Colors.grey,
          title: Text(
            itemTitle,
          ),
          enabled: isEnabled,
        ),
      ),
    );
  }

  Widget _buildSyncButton() => BlocBuilder<SyncCubit, SyncState>(
        builder: (context, syncState) => IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () {
            print('Starting Sync Manually');
            context.read<ArDriveAnalytics>().trackScreenEvent(
                screenName: "mainMenu", eventName: "manualSync");
            context.read<SyncCubit>().startSync();
          },
          tooltip: appLocalizationsOf(context).sync,
        ),
      );
}
