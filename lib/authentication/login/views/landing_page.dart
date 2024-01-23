import 'package:ardrive/authentication/components/button.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../misc/resources.dart';
import '../../components/login_card.dart';
import '../../components/max_device_sizes_constrained_box.dart';

class LandingPageView extends StatefulWidget {
  const LandingPageView({
    super.key,
  });

  @override
  State<LandingPageView> createState() => _LandingPageViewState();
}

class _LandingPageViewState extends State<LandingPageView> {
  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    // FIXME: add switching of typography based on screen size
    final typography = ArDriveTypographyNew.desktop;

    return MaxDeviceSizesConstrainedBox(
      defaultMaxWidth: 512,
      defaultMaxHeight: 798,
      maxHeightPercent: 0.9,
      child: SingleChildScrollView(
        child: LoginCard(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ArDriveImage(
                image: AssetImage(Resources.images.brand.logo1),
                height: 50,
              ),
              heightSpacing(),
              Align(
                alignment: Alignment.topCenter,
                child: Text(
                  // FIXME: Add localization key
                  'Welcome to ArDrive',
                  style: typography.heading1(fontWeight: ArFontWeight.bold),
                ),
              ),
              heightSpacing(),
              //FIXME: Add localization key
              Text('Are you an existing user or a new user?',
                  style: typography.paragraphLarge(
                      color: colors.themeFgSubtle,
                      fontWeight: ArFontWeight.semiBold)),
              const SizedBox(height: 72),
              ArDriveButtonNew(
                  text: 'Existing user',
                  typography: typography,
                  maxWidth: double.maxFinite,
                  onPressed: () {
                    context
                        .read<LoginBloc>()
                        .add(const SelectLoginFlow(existingUser: true));
                  }),
              const SizedBox(height: 16),
              ArDriveButtonNew(
                  text: 'New User',
                  typography: typography,
                  maxWidth: double.maxFinite,
                  onPressed: () {
                    context
                        .read<LoginBloc>()
                        .add(const SelectLoginFlow(existingUser: false));
                  }),
            ],
          ),
        ),
      ),
    );
  }

  SizedBox heightSpacing() {
    return SizedBox(
        height: MediaQuery.of(context).size.height < 700 ? 12.0 : 16.0);
  }
}
