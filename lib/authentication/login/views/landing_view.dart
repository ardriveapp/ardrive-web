import 'package:ardrive/authentication/components/button.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/components/app_version_widget.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../misc/resources.dart';
import '../../components/login_card.dart';

class LandingView extends StatefulWidget {
  const LandingView({
    super.key,
  });

  @override
  State<LandingView> createState() => _LandingViewState();
}

class _LandingViewState extends State<LandingView> {
  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return SizedBox(
      width: 381,
      child: LoginCard(
        content: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  textAlign: TextAlign.center,
                  style: typography.heading1(
                      color: colorTokens.textHigh,
                      fontWeight: ArFontWeight.bold),
                ),
              ),
              heightSpacing(),
              //FIXME: Add localization key
              Text('Are you an existing user or a new user?',
                  textAlign: TextAlign.center,
                  style: typography.paragraphLarge(
                      color: colorTokens.textLow,
                      fontWeight: ArFontWeight.semiBold)),
              const SizedBox(height: 72),
              ArDriveButtonNew(
                  text: 'Log In',
                  typography: typography,
                  maxWidth: double.maxFinite,
                  onPressed: () {
                    PlausibleEventTracker.trackClickLogin();

                    context
                        .read<LoginBloc>()
                        .add(const SelectLoginFlow(existingUser: true));
                  }),
              const SizedBox(height: 16),
              ArDriveButtonNew(
                  text: 'Sign Up',
                  typography: typography,
                  maxWidth: double.maxFinite,
                  variant: ButtonVariant.primary,
                  onPressed: () {
                    PlausibleEventTracker.trackClickSignUp();

                    context
                        .read<LoginBloc>()
                        .add(const SelectLoginFlow(existingUser: false));
                  }),
              const SizedBox(height: 72),
              AppVersionWidget(
                color: colorTokens.textLow,
              ),
            ]),
      ),
    );
  }

  SizedBox heightSpacing() {
    return SizedBox(
        height: MediaQuery.of(context).size.height < 700 ? 12.0 : 16.0);
  }
}
