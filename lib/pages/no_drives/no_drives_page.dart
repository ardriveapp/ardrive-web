import 'package:ardrive/app_shell.dart';
import 'package:ardrive/authentication/components/login_modal.dart';
import 'package:ardrive/blocs/drive_detail/drive_detail_cubit.dart';
import 'package:ardrive/components/app_top_bar.dart';
import 'package:ardrive/components/drive_create_form.dart';
import 'package:ardrive/components/profile_card.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/pages/drive_detail/drive_detail_page.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:ardrive/authentication/login/views/modals/open_drive_modal.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';

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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SyncButton(),
                SizedBox(width: 8),
                SizedBox(width: 8),
                ProfileCard(),
              ],
            ),
            const SizedBox(
              height: 24,
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
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
                                    anonymouslyShowDriveDetail
                                        ? appLocalizationsOf(context)
                                            .openDriveEmptyTitle
                                        : 'Getting started',
                                    style: typography.heading2(
                                      color: colorTokens.textHigh,
                                      fontWeight: ArFontWeight.semiBold,
                                    ),
                                  ),
                                  Text(
                                    anonymouslyShowDriveDetail
                                        ? appLocalizationsOf(context)
                                            .openDriveEmptyDescription
                                        : 'Create a new drive to start uploading your files.',
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
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: anonymouslyShowDriveDetail
                          ? _openDriveCard(context: context)
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _publicDrivesCard(context: context),
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
                                    'or',
                                    style: typography.paragraphNormal(
                                      fontWeight: ArFontWeight.semiBold,
                                      color: colorTokens.textHigh,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 35),
                                _privateDrivesCard(context: context),
                              ],
                            ),
                    ),
                    const SizedBox.shrink()
                  ],
                ),
              ),
            ),
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
          fit: StackFit.expand,
          children: [
            Positioned(
              bottom: 0,
              right: 0,
              child: SvgPicture.asset(
                Resources.images.login.bannerLightMode,
                fit: BoxFit.cover,
              ),
            ),
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.max,
                children: [
                  const SizedBox(height: 24),
                  Text(
                    anonymouslyShowDriveDetail
                        ? appLocalizationsOf(context).openDriveEmptyTitle
                        : 'Getting started',
                    style: typography.heading2(
                      color: colorTokens.textHigh,
                      fontWeight: ArFontWeight.semiBold,
                    ),
                  ),
                  Text(
                    anonymouslyShowDriveDetail
                        ? appLocalizationsOf(context).openDriveEmptyDescription
                        : 'Create a new drive to start uploading your files.',
                    style: typography.paragraphLarge(
                      fontWeight: ArFontWeight.semiBold,
                      color: colorTokens.textLow,
                    ),
                  ),
                  const SizedBox(height: 40),
                  if (anonymouslyShowDriveDetail)
                    _openDriveCard(context: context)
                  else ...[
                    _publicDrivesCard(context: context),
                    const SizedBox(height: 20),
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colorTokens.containerL2,
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'or',
                        style: typography.paragraphNormal(
                          fontWeight: ArFontWeight.semiBold,
                          color: colorTokens.textHigh,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _privateDrivesCard(context: context),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What a visitor with no local drives is offered instead of the two create
/// cards: creating a drive needs a wallet they do not have, and both of those
/// buttons were dead for them.
ArDriveLoginModal _openDriveCard({
  required BuildContext context,
}) {
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
  final typography = ArDriveTypographyNew.of(context);
  final strings = appLocalizationsOf(context);

  return ArDriveLoginModal(
    padding: const EdgeInsets.all(40),
    hasCloseButton: false,
    content: Column(
      children: [
        ArDriveIcons.iconAttachDrive(),
        const SizedBox(height: 12),
        Text(
          strings.openDriveTitle,
          style: typography.paragraphXLarge(
            fontWeight: ArFontWeight.semiBold,
            color: colorTokens.textHigh,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          strings.openDriveDescription,
          style: typography.paragraphNormal(
            fontWeight: ArFontWeight.book,
            color: colorTokens.textMid,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        ArDriveButtonNew(
          size: ArDriveButtonSize.large,
          maxWidth: double.infinity,
          key: const Key('noDrivesOpenDrive'),
          text: strings.openDriveButton,
          typography: typography,
          variant: ButtonVariant.primary,
          onPressed: () => showOpenDriveDialog(context),
        ),
      ],
    ),
  );
}

ArDriveLoginModal _privateDrivesCard({
  required BuildContext context,
}) {
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
  final typography = ArDriveTypographyNew.of(context);

  return ArDriveLoginModal(
    padding: const EdgeInsets.all(40),
    hasCloseButton: false,
    content: Column(
      children: [
        ArDriveIcons.privateDrive(),
        const SizedBox(height: 12),
        Text(
          'Private drive',
          style: typography.paragraphXLarge(
            fontWeight: ArFontWeight.semiBold,
            color: colorTokens.textHigh,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Encrypted. Only you and the people you share it with can see what is in it.',
          style: typography.paragraphNormal(
            fontWeight: ArFontWeight.book,
            color: colorTokens.textMid,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        ArDriveButtonNew(
          size: ArDriveButtonSize.large,
          maxWidth: double.infinity,
          text: 'Create new private drive',
          typography: typography,
          variant: ButtonVariant.primary,
          onPressed: () {
            PlausibleEventTracker.trackClickCreatePrivateDriveButton(
              PlausiblePageView.fileExplorerNewUserEmpty,
            );
            promptToCreateDrive(context, privacy: DrivePrivacy.private);
          },
        ),
      ],
    ),
  );
}

ArDriveLoginModal _publicDrivesCard({
  required BuildContext context,
}) {
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
  final typography = ArDriveTypographyNew.of(context);

  return ArDriveLoginModal(
    padding: const EdgeInsets.all(40),
    hasCloseButton: false,
    content: Column(
      children: [
        ArDriveIcons.publicDrive(),
        const SizedBox(height: 12),
        Text(
          'Public drive',
          style: typography.paragraphXLarge(
            fontWeight: ArFontWeight.semiBold,
            color: colorTokens.textHigh,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Anyone can find it and see what is in it.',
          style: typography.paragraphNormal(
            fontWeight: ArFontWeight.book,
            color: colorTokens.textMid,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        ArDriveButtonNew(
          size: ArDriveButtonSize.large,
          maxWidth: double.infinity,
          text: 'Create new public drive',
          typography: typography,
          variant: ButtonVariant.primary,
          onPressed: () {
            PlausibleEventTracker.trackClickCreatePublicDriveButton(
              PlausiblePageView.fileExplorerNewUserEmpty,
            );
            promptToCreateDrive(context, privacy: DrivePrivacy.public);
          },
        ),
      ],
    ),
  );
}

/// The Getting Started screen's content, without the page around it.
///
/// Extracted so the drives list's empty state is literally this screen rather
/// than a second one that drifts away from it. It is the right answer for
/// exactly one situation - an account that genuinely has no drives - and both
/// callers are careful to show it only then.
/// The width both cards need before they can sit side by side.
///
/// Measured, not guessed: the Row wants ~828.5px and renders clean from 878.
const double _gettingStartedCardsSideBySide = 878;

class GettingStartedCards extends StatelessWidget {
  const GettingStartedCards({super.key});

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final children = [
          _publicDrivesCard(context: context),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: colorTokens.containerL2,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'or',
              style: typography.paragraphNormal(
                fontWeight: ArFontWeight.semiBold,
                color: colorTokens.textHigh,
              ),
            ),
          ),
          _privateDrivesCard(context: context),
        ];

        // Side by side only where both cards genuinely fit. The pair needs
        // ~828px (two fixed 283px cards, a 35px gap and their padding), and a
        // threshold measured lower than that clips the second card against the
        // window edge for every width in between - which is the whole of a
        // laptop half-screen. Rendered clean from 878 up.
        if (constraints.maxWidth < _gettingStartedCardsSideBySide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (final child in children) ...[
                child,
                const SizedBox(height: 20),
              ],
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final child in children) ...[
              child,
              const SizedBox(width: 35),
            ],
          ]..removeLast(),
        );
      },
    );
  }
}
