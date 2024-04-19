import 'package:ardrive/app_shell.dart';
import 'package:ardrive/authentication/components/login_modal.dart';
import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/components/drive_create_form.dart';
import 'package:ardrive/components/profile_card.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:responsive_builder/responsive_builder.dart';

import '../../gift/reedem_button.dart';

/// A page letting the user know that they have no personal or attached drives
/// with a call to action for them to add new ones.
class NoDrivesPage extends StatelessWidget {
  final bool anonymouslyShowDriveDetail;

  NoDrivesPage({
    super.key,
    required this.anonymouslyShowDriveDetail,
  }) {
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
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return ScreenTypeLayout.builder(
      desktop: (context) => Padding(
        padding: const EdgeInsets.only(top: 32, right: 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
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
              const SizedBox(
                height: 24,
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    LayoutBuilder(builder: (context, constraints) {
                      return SizedBox(
                        height: MediaQuery.of(context).size.height * 0.3,
                        width: constraints.maxWidth,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(12),
                                topRight: Radius.circular(12),
                              ),
                              child: SvgPicture.asset(
                                Resources.images.login.bannerLightMode,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Getting Stated',
                                    style: typography.heading2(
                                      color: colorTokens.textHigh,
                                    ),
                                  ),
                                  Text(
                                    'Create a new drive to start uploading your files.',
                                    style: typography.paragraphLarge(
                                      fontWeight: ArFontWeight.semiBold,
                                      color: colorTokens.textLow,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ArDriveLoginModal(
                            padding: const EdgeInsets.all(40),
                            hasCloseButton: false,
                            content: Column(
                              children: [
                                ArDriveIcons.addDrive(),
                                const SizedBox(height: 12),
                                Text(
                                  'Public Drive',
                                  style: typography.paragraphXLarge(
                                    fontWeight: ArFontWeight.semiBold,
                                    color: colorTokens.textHigh,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Public Drives are discoverable, meaning that others can find and view the contents.',
                                  style: typography.paragraphNormal(
                                    fontWeight: ArFontWeight.semiBold,
                                    color: colorTokens.textLow,
                                  ),
                                ),
                                const SizedBox(height: 32),
                                ArDriveButtonNew(
                                  text: 'Create Public Drive',
                                  typography: typography,
                                  variant: ButtonVariant.primary,
                                  onPressed: () {
                                    promptToCreateDrive(context,
                                        privacy: DrivePrivacy.public);
                                  },
                                ),
                              ],
                            )),
                        const SizedBox(width: 35),
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: colorTokens.containerL2,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Text(
                            'Or',
                            style: typography.paragraphNormal(
                              fontWeight: ArFontWeight.semiBold,
                              color: colorTokens.textHigh,
                            ),
                          ),
                        ),
                        const SizedBox(width: 35),
                        ArDriveLoginModal(
                            padding: const EdgeInsets.all(40),
                            hasCloseButton: false,
                            content: Column(
                              children: [
                                ArDriveIcons.addDrive(),
                                const SizedBox(height: 12),
                                Text(
                                  'Private Drive',
                                  style: typography.paragraphXLarge(
                                    fontWeight: ArFontWeight.semiBold,
                                    color: colorTokens.textHigh,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Private Drives offer state-of-the-art security, so you can control who can access the content.',
                                  style: typography.paragraphNormal(
                                    fontWeight: ArFontWeight.semiBold,
                                    color: colorTokens.textLow,
                                  ),
                                ),
                                const SizedBox(height: 32),
                                ArDriveButtonNew(
                                  text: 'Create new private drive',
                                  typography: typography,
                                  variant: ButtonVariant.primary,
                                  onPressed: () {
                                    promptToCreateDrive(context,
                                        privacy: DrivePrivacy.private);
                                  },
                                ),
                              ],
                            )),
                      ],
                    ),
                    const SizedBox.shrink()
                  ],
                ),
              ),
            ],
          ),
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
}
