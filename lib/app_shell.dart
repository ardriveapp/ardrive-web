import 'package:ardrive/components/profile_card.dart';
import 'package:ardrive/components/side_bar.dart';
import 'package:ardrive/utils/html/html_util.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
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
    Key? key,
    required this.page,
  }) : super(key: key);

  @override
  AppShellState createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  bool _showProfileOverlay = false;
  bool _showWalletSwitchDialog = true;
  @override
  Widget build(BuildContext context) => BlocBuilder<DrivesCubit, DrivesState>(
        builder: (context, state) {
          onArConnectWalletSwitch(() {
            if (_showWalletSwitchDialog) {
              showDialog(
                context: context,
                builder: (context) => const WalletSwitchDialog(),
              );
            }
            //Used to prevent the dialog being shown multiple times.
            _showWalletSwitchDialog = false;
          });

          Widget buildPage(scaffold) => Material(
                child: BlocBuilder<SyncCubit, SyncState>(
                  builder: (context, syncState) => syncState is SyncInProgress
                      ? Stack(
                          children: [
                            AbsorbPointer(
                              child: scaffold,
                            ),
                            SizedBox.expand(
                              child: Container(
                                color: Colors.black.withOpacity(0.5),
                              ),
                            ),
                            BlocBuilder<ProfileCubit, ProfileState>(
                              builder: (context, state) {
                                return FutureBuilder(
                                  future: context
                                      .read<ProfileCubit>()
                                      .isCurrentProfileArConnect(),
                                  builder: (BuildContext context,
                                      AsyncSnapshot snapshot) {
                                    return Align(
                                      alignment: Alignment.center,
                                      child: Material(
                                        borderRadius: BorderRadius.circular(8),
                                        child: ProgressDialog(
                                            progressBar: ProgressBar(
                                              percentage: context
                                                  .read<SyncCubit>()
                                                  .syncProgressController
                                                  .stream,
                                            ),
                                            percentageDetails: _syncStreamBuilder(
                                                builderWithData: (syncProgress) =>
                                                    Text(appLocalizationsOf(
                                                            context)
                                                        .syncProgressPercentage(
                                                            (syncProgress.progress *
                                                                    100)
                                                                .roundToDouble()
                                                                .toString()))),
                                            progressDescription:
                                                _syncStreamBuilder(
                                              builderWithData: (syncProgress) =>
                                                  Text(
                                                syncProgress.drivesCount == 0
                                                    ? ''
                                                    : syncProgress.drivesCount >
                                                            1
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
                                                style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight:
                                                        FontWeight.bold),
                                              ),
                                            ),
                                            title: snapshot.data ?? false
                                                ? appLocalizationsOf(context)
                                                    .syncingPleaseRemainOnThisTab
                                                : appLocalizationsOf(context)
                                                    .syncingPleaseWait),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ],
                        )
                      : scaffold,
                ),
              );
          return ScreenTypeLayout(
            desktop: buildPage(
              Row(
                children: [
                  const AppSideBar(),
                  Expanded(
                    child: Scaffold(
                      body: widget.page,
                    ),
                  ),
                ],
              ),
            ),
            mobile: buildPage(
              widget.page,
            ),
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

class MobileAppBar extends StatelessWidget implements PreferredSizeWidget {
  const MobileAppBar({super.key, this.leading});

  final Widget? leading;

  @override
  Size get preferredSize =>
      const Size.fromHeight(80); // Set the height of the appbar

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        height: 80,
        color: ArDriveTheme.of(context).themeData.tableTheme.cellColor,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            leading ??
                IconButton(
                  icon: ArDriveIcons.menuArrow(
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeFgDefault,
                  ),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
            const Spacer(),
            const SyncButton(),
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
