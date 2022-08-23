import 'package:ardrive/services/analytics/ardrive_analytics.dart';
import 'package:ardrive/utils/html/html_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_portal/flutter_portal.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:url_launcher/url_launcher.dart';

import 'blocs/blocs.dart';
import 'components/components.dart';
import 'components/progress_bar.dart';
import 'components/wallet_switch_dialog.dart';
import 'utils/app_localizations_wrapper.dart';

class AppShell extends StatefulWidget {
  final Widget page;

  const AppShell({Key? key, required this.page}) : super(key: key);

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
          AppBar _buildAppBar() => AppBar(
                // title: Image.asset(
                //   R.images.brand.logoHorizontalNoSubtitle,
                //   height: 64,
                //   fit: BoxFit.contain,
                // ),
                elevation: 0.0,
                backgroundColor: Colors.transparent,
                actions: [
                  IconButton(
                      icon: const Icon(Icons.people_alt),
                      tooltip: 'CommunityXYZ',
                      onPressed: () {
                        context.read<ArDriveAnalytics>().trackScreenEvent(
                              screenName: "driveExplorer",
                              eventName: "communityXYZButton",
                            );
                        launchUrl(Uri.parse(
                          'https://community.xyz/#-8A6RexFkpfWwuyVO98wzSFZh0d6VJuI-buTJvlwOJQ',
                        ));
                      }),
                  IconButton(
                      icon: PortalEntry(
                        visible: _showProfileOverlay,
                        portal: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              final eventName = _showProfileOverlay
                                  ? "hideProfile"
                                  : "showProfile";
                              context.read<ArDriveAnalytics>().trackScreenEvent(
                                    screenName: "driveExplorer",
                                    eventName: eventName,
                                  );
                              toggleProfileOverlay();
                            }),
                        child: PortalEntry(
                          visible: _showProfileOverlay,
                          portal: const Padding(
                            padding: EdgeInsets.only(top: 56),
                            child: ProfileOverlay(),
                          ),
                          portalAnchor: Alignment.topRight,
                          childAnchor: Alignment.topRight,
                          child: const Icon(Icons.account_circle),
                        ),
                      ),
                      tooltip: appLocalizationsOf(context).profile,
                      onPressed: () {
                        final eventName =
                            _showProfileOverlay ? "hideProfile" : "showProfile";
                        context.read<ArDriveAnalytics>().trackScreenEvent(
                              screenName: "driveExplorer",
                              eventName: eventName,
                            );
                        toggleProfileOverlay();
                      }),
                ],
              );
          Widget _buildPage(scaffold) => BlocBuilder<SyncCubit, SyncState>(
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
                                  return ProgressDialog(
                                      progressBar: ProgressBar(
                                        percentage: context
                                            .read<SyncCubit>()
                                            .syncProgressController
                                            .stream,
                                      ),
                                      percentageDetails: _syncStreamBuilder(
                                          builderWithData: (syncProgress) =>
                                              Text(appLocalizationsOf(context)
                                                  .syncProgressPercentage(
                                                      (syncProgress.progress *
                                                              100)
                                                          .roundToDouble()
                                                          .toString()))),
                                      progressDescription: _syncStreamBuilder(
                                        builderWithData: (syncProgress) => Text(
                                          syncProgress.drivesCount == 0
                                              ? ''
                                              : syncProgress.drivesCount > 1
                                                  ? appLocalizationsOf(context)
                                                      .driveSyncedOfDrivesCount(
                                                          syncProgress
                                                              .drivesSynced,
                                                          syncProgress
                                                              .drivesCount)
                                                  : appLocalizationsOf(context)
                                                      .syncingOnlyOneDrive,
                                          style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      title: snapshot.data ?? false
                                          ? appLocalizationsOf(context)
                                              .syncingPleaseRemainOnThisTab
                                          : appLocalizationsOf(context)
                                              .syncingPleaseWait);
                                },
                              );
                            },
                          ),
                        ],
                      )
                    : scaffold,
              );
          return ScreenTypeLayout(
            desktop: _buildPage(
              Row(
                children: [
                  const AppDrawer(),
                  Expanded(
                    child: Scaffold(
                      appBar: _buildAppBar(),
                      body: widget.page,
                    ),
                  ),
                ],
              ),
            ),
            mobile: _buildPage(
              Scaffold(
                appBar: _buildAppBar(),
                drawer: const AppDrawer(),
                body: Row(
                  children: [
                    Expanded(
                      child: widget.page,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

  Widget _syncStreamBuilder(
          {required Widget Function(SyncProgress s) builderWithData}) =>
      StreamBuilder<SyncProgress>(
          stream: context.read<SyncCubit>().syncProgressController.stream,
          builder: (context, snapshot) =>
              snapshot.hasData ? builderWithData(snapshot.data!) : Container());

  void toggleProfileOverlay() =>
      setState(() => _showProfileOverlay = !_showProfileOverlay);
}
