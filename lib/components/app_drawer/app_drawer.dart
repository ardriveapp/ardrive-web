import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/app_drawer/drive_list_tile.dart';
import 'package:ardrive/components/new_button.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/models/enums.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/inferno_rules_url.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
                            context,
                            state,
                            profileState,
                          );
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
                                onPressed: () =>
                                    openUrl(url: Resources.helpLink),
                                child: const Icon(Icons.help_outline),
                              ),
                            ),
                            const AppVersionWidget()
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
                                final localeName =
                                    appLocalizationsOf(context).localeName;
                                final infernoUrl =
                                    getInfernoUrlForCurrentLocalization(
                                        localeName);

                                openUrl(url: infernoUrl);
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

  Widget _buildDriveActionsButton(
    BuildContext context,
    DrivesState drivesState,
    ProfileState profileState,
  ) {
    final theme = Theme.of(context);
    final minimumWalletBalance = BigInt.from(10000000);

    if (profileState.runtimeType == ProfileLoggedIn) {
      final profile = profileState as ProfileLoggedIn;
      final notEnoughARInWallet = !profile.hasMinimumBalanceForUpload(
        minimumWalletBalance: minimumWalletBalance,
      );
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
                  builder: (context, driveDetailState) => buildNewButton(
                    context,
                    drivesState: drivesState,
                    profileState: profile,
                    driveDetailState: driveDetailState,
                    button: _buildNewButton(context),
                  ),
                ),
              ),
            ),
          ),
          if (notEnoughARInWallet) ...{
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
              onPressed: () => openUrl(url: Resources.arHelpLink),
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
            child: BlocBuilder<DriveDetailCubit, DriveDetailState>(
              builder: (context, driveDetailState) => buildNewButton(
                context,
                drivesState: drivesState,
                profileState: profileState,
                driveDetailState: driveDetailState,
                button: _buildNewButton(context),
              ),
            ),
          ),
        ),
      );
    }
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
