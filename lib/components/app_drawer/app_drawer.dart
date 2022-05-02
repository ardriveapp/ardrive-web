import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/app_drawer/drive_list_tile.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
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
                        SizedBox(
                          height: 32,
                        ),
                        _buildLogo(),
                        SizedBox(
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
                                padding: EdgeInsets.all(21),
                                key: PageStorageKey<String>('driveScrollView'),
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
                                        onPressed: () => context
                                            .read<DrivesCubit>()
                                            .selectDrive(d.id),
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
                    padding: EdgeInsets.all(21),
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: FloatingActionButton(
                            elevation: 0,
                            tooltip: appLocalizationsOf(context).help,
                            onPressed: () => launch(
                                'https://ardrive.typeform.com/to/pGeAVvtg'),
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
                              return SizedBox(height: 32, width: 32);
                            }
                          },
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
        R.images.brand.logoHorizontalNoSubtitleDark,
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
                        // TODO(@thiagocarvalhodev): add the tooltip and `hasMinimumWalletBalance` validation

                        _buildNewFolderItem(context, state,
                            profile.walletBalance >= minimumWalletBalance),
                        PopupMenuDivider(),
                        _buildUploadFileItem(context, state,
                            profile.walletBalance >= minimumWalletBalance),
                        _buildUploadFolderItem(context, state,
                            profile.walletBalance >= minimumWalletBalance),
                        PopupMenuDivider(),
                      },
                      if (drivesState is DrivesLoadSuccess) ...{
                        // TODO(@thiagocarvalhodev): add the tooltip and `hasMinimumWalletBalance` validation

                        _buildCreateDrive(context, drivesState,
                            profile.walletBalance >= minimumWalletBalance),
                        _buildAttachDrive(context)
                      },
                      if (state is DriveDetailLoadSuccess &&
                          state.currentDrive.privacy == 'public') ...{
                        // TODO(@thiagocarvalhodev): add the tooltip and `hasMinimumWalletBalance` validation

                        _buildCreateManifestItem(state, context)
                      },
                    ],
                    child: _buildNewButton(context),
                  ),
                ),
              ),
            ),
          ),
          if (profile.walletBalance < minimumWalletBalance) ...{
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
              onPressed: () => launch(R.arHelpLink),
              child: Text(
                appLocalizationsOf(context).howDoIGetAR,
                style: TextStyle(
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
      context, DriveDetailLoadSuccess state, bool hasMinimumWalletBalance) {
    return PopupMenuItem(
      enabled: state.hasWritePermissions,
      value: (context) => promptToCreateFolder(
        context,
        driveId: state.currentDrive.id,
        parentFolderId: state.folderInView.folder.id,
      ),
      child: ListTile(
        enabled: state.hasWritePermissions && hasMinimumWalletBalance,
        title: Text(appLocalizationsOf(context).newFolder),
      ),
    );
  }

  PopupMenuEntry<Function> _buildUploadFileItem(
      context, DriveDetailLoadSuccess state, bool hasMinimumWalletBalance) {
    return PopupMenuItem(
      enabled: state.hasWritePermissions,
      value: (context) => promptToUpload(
        context,
        driveId: state.currentDrive.id,
        folderId: state.folderInView.folder.id,
        isFolderUpload: false,
      ),
      // TODO(@thiagocarvalhodev): add the tooltip and `hasMinimumWalletBalance` validation

      child: ListTile(
        enabled: state.hasWritePermissions,
        title: Text(
          appLocalizationsOf(context).uploadFiles,
        ),
      ),
    );
  }

  PopupMenuEntry<Function> _buildUploadFolderItem(
      context, DriveDetailLoadSuccess state, bool hasMinimumWalletBalance) {
    return PopupMenuItem(
      enabled: state.hasWritePermissions,
      value: (context) => promptToUpload(
        context,
        driveId: state.currentDrive.id,
        folderId: state.folderInView.folder.id,
        isFolderUpload: true,
      ),
      // TODO(@thiagocarvalhodev): add the tooltip and `hasMinimumWalletBalance` validation
      child: ListTile(
        enabled: state.hasWritePermissions,
        title: Text(
          appLocalizationsOf(context).uploadFolder,
        ),
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

  PopupMenuEntry<Function> _buildCreateDrive(BuildContext context,
      DrivesLoadSuccess drivesState, bool hasMinimumWalletBalance) {
    return PopupMenuItem(
      enabled: drivesState.canCreateNewDrive && hasMinimumWalletBalance,
      value: (context) => promptToCreateDrive(context),
      child: Tooltip(
        message: hasMinimumWalletBalance
            ? ''
            : 'Only wallets with AR can create New Drives',
        child: ListTile(
          textColor: hasMinimumWalletBalance
              ? ListTileTheme.of(context).textColor
              : Colors.grey,
          enabled: drivesState.canCreateNewDrive,
          title: Text(appLocalizationsOf(context).newDrive),
        ),
      ),
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
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  PopupMenuEntry<Function> _buildCreateManifestItem(context, state) {
    return PopupMenuItem(
      value: (context) =>
          promptToCreateManifest(context, drive: state.currentDrive),
      enabled: !state.driveIsEmpty,
      child: ListTile(
        title: Text(
          appLocalizationsOf(context).createManifest,
        ),
        enabled: !state.driveIsEmpty,
      ),
    );
  }

  Widget _buildSyncButton() => BlocBuilder<SyncCubit, SyncState>(
        builder: (context, syncState) => IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => context.read<SyncCubit>().startSync(),
          tooltip: appLocalizationsOf(context).sync,
        ),
      );
}
