import 'package:ardrive/app_shell.dart';
import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/components/profile_card.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

/// A page letting the user know that they have no personal or attached drives
/// with a call to action for them to add new ones.
class NoDrivesPage extends StatelessWidget {
  const NoDrivesPage({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => ScreenTypeLayout(
        desktop: Padding(
          padding: const EdgeInsets.only(top: 32, right: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: const [
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
        mobile: Scaffold(
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
