import 'package:ardrive/app_shell.dart';
import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/components/profile_card.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

import '../../gift/reedem_button.dart';

/// A page letting the user know that they have no personal or attached drives
/// with a call to action for them to add new ones.
class NoDrivesPage extends StatelessWidget {
  final bool anonymouslyShowDriveDetail;

  NoDrivesPage({
    Key? key,
    required this.anonymouslyShowDriveDetail,
  }) : super(key: key) {
    if (anonymouslyShowDriveDetail) {
      PlausibleEventTracker.trackPageview(
        page: PlausiblePageView.fileExplorerNonLoggedInUser,
      );

      PlausibleEventTracker.trackPageview(
        page: PlausiblePageView.fileExplorerPage,
        props: {
          'loggedIn': false,
          'noDrives': true,
        },
      );
    } else {
      PlausibleEventTracker.trackPageview(
        page: PlausiblePageView.fileExplorerNewUserEmpty,
      );

      PlausibleEventTracker.trackPageview(
        page: PlausiblePageView.fileExplorerPage,
        props: {
          'loggedIn': true,
          'noDrives': true,
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) => ScreenTypeLayout.builder(
        desktop: (context) => Padding(
          padding: const EdgeInsets.only(top: 32, right: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  RedeemButton(),
                  SizedBox(width: 24),
                  ProfileCard(),
                ],
              ),
              Center(
                child: Text(
                  appLocalizationsOf(context).noDrives,
                  textAlign: TextAlign.center,
                  style: ArDriveTypography.headline.headline5Regular(),
                ),
              ),
              const SizedBox(),
            ],
          ),
        ),
        mobile: (context) => Scaffold(
          bottomNavigationBar: BlocBuilder<DriveDetailCubit, DriveDetailState>(
            builder: (context, state) {
              return const CustomBottomNavigation();
            },
          ),
          appBar: const MobileAppBar(
            showDrawerButton: false,
          ),
          body: Stack(
            children: [
              Center(
                child: Text(
                  appLocalizationsOf(context).noDrives,
                  textAlign: TextAlign.center,
                  style: ArDriveTypography.headline.headline5Regular(),
                ),
              ),
            ],
          ),
        ),
      );
}
