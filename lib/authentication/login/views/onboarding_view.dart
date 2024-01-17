import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

import '../../../misc/misc.dart';
import '../../../utils/app_localizations_wrapper.dart';
import '../../../utils/plausible_event_tracker/plausible_event_tracker.dart';
import '../../components/fadethrough_transition_switcher.dart';
import '../../components/max_device_sizes_constrained_box.dart';
import '../blocs/login_bloc.dart';

class OnBoardingView extends StatefulWidget {
  const OnBoardingView({
    super.key,
    required this.wallet,
  });
  final Wallet wallet;

  @override
  State<OnBoardingView> createState() => OnBoardingViewState();
}

class OnBoardingViewState extends State<OnBoardingView> {
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();

    PlausibleEventTracker.trackPageview(page: PlausiblePageView.onboardingPage)
        .then(
      (value) {
        PlausibleEventTracker.trackPageview(
            page: PlausiblePageView.tutorialsPage1);
      },
    );
  }

  List<_OnBoarding> get _list => [
        _OnBoarding(
          primaryButtonText: appLocalizationsOf(context).next,
          primaryButtonAction: () {
            _goToNextPage();
          },
          secundaryButtonHasIcon: false,
          secundaryButtonText: appLocalizationsOf(context).skip,
          secundaryButtonAction: () {
            context.read<LoginBloc>().add(
                  FinishOnboarding(
                    wallet: widget.wallet,
                  ),
                );
            PlausibleEventTracker.trackPageview(
                page: PlausiblePageView.tutorialSkipped);
          },
          title: appLocalizationsOf(context).onboarding1Title,
          description: appLocalizationsOf(context).onboarding1Description,
          illustration: AssetImage(Resources.images.login.gridImage),
        ),
        _OnBoarding(
          primaryButtonText: appLocalizationsOf(context).next,
          primaryButtonAction: () {
            _goToNextPage();
          },
          secundaryButtonText: appLocalizationsOf(context).backButtonOnboarding,
          secundaryButtonAction: () {
            _goToPreviousPage();
          },
          title: appLocalizationsOf(context).onboarding2Title,
          description: appLocalizationsOf(context).onboarding2Description,
          illustration: AssetImage(Resources.images.login.gridImage),
        ),
        _OnBoarding(
          primaryButtonText: appLocalizationsOf(context).diveInButtonOnboarding,
          primaryButtonAction: () {
            context.read<LoginBloc>().add(
                  FinishOnboarding(
                    wallet: widget.wallet,
                  ),
                );
          },
          secundaryButtonText: appLocalizationsOf(context).backButtonOnboarding,
          secundaryButtonAction: () {
            _goToPreviousPage();
          },
          title: appLocalizationsOf(context).onboarding3Title,
          description: appLocalizationsOf(context).onboarding3Description,
          illustration: AssetImage(Resources.images.login.gridImage),
        ),
      ];

  void _goToNextPage() {
    _goToPage(_currentPage + 1);
  }

  void _goToPreviousPage() {
    _goToPage(_currentPage - 1);
  }

  void _goToPage(int page) {
    setState(() {
      _currentPage = page;
    });

    if (_currentPage == 0) {
      PlausibleEventTracker.trackPageview(
          page: PlausiblePageView.tutorialsPage1);
    } else if (_currentPage == 1) {
      PlausibleEventTracker.trackPageview(
          page: PlausiblePageView.tutorialsPage2);
    } else if (_currentPage == 2) {
      PlausibleEventTracker.trackPageview(
          page: PlausiblePageView.tutorialsPage3);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenTypeLayout.builder(
      desktop: (context) => Material(
        color: ArDriveTheme.of(context).themeData.colors.themeBgCanvas,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Container(
                color: ArDriveTheme.of(context).themeData.colors.themeBgSurface,
                child: Align(
                  child: MaxDeviceSizesConstrainedBox(
                    child: FadeThroughTransitionSwitcher(
                      fillColor: ArDriveTheme.of(context)
                          .themeData
                          .colors
                          .themeBgSurface,
                      child: _buildOnBoardingContent(),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: FractionallySizedBox(
                heightFactor: 1,
                child: _buildOnBoardingIllustration(_currentPage),
              ),
            ),
          ],
        ),
      ),
      mobile: (context) => Scaffold(
        resizeToAvoidBottomInset: true,
        body: Container(
          color: ArDriveTheme.of(context).themeData.colors.themeBgCanvas,
          child: Align(
            child: MaxDeviceSizesConstrainedBox(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _buildOnBoardingContent(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOnBoardingIllustration(int index) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: 0.25,
          child: ArDriveImage(
            image: _list[_currentPage].illustration,
            fit: BoxFit.cover,
            height: double.maxFinite,
            width: double.maxFinite,
          ),
        ),
        Align(
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ArDriveImage(
                image: AssetImage(
                  Resources.images.login.ardriveLogoOnboarding,
                ),
                fit: BoxFit.contain,
                height: 240,
                width: 240,
              ),
              const SizedBox(
                height: 48,
              ),
              Align(
                alignment: Alignment.topCenter,
                child: ArDrivePaginationDots(
                  currentPage: _currentPage,
                  numberOfPages: _list.length,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOnBoardingContent() {
    return _OnBoardingContent(
      key: ValueKey(_currentPage),
      onBoarding: _list[_currentPage],
    );
  }
}

class _OnBoardingContent extends StatelessWidget {
  final _OnBoarding onBoarding;

  const _OnBoardingContent({
    super.key,
    required this.onBoarding,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        Text(
          onBoarding.title,
          style: ArDriveTypography.headline.headline3Bold(),
        ),
        Text(
          onBoarding.description,
          style: ArDriveTypography.body.buttonXLargeBold(),
        ),
        Row(
          key: const ValueKey('buttons'),
          children: [
            ArDriveButton(
              icon: onBoarding.secundaryButtonHasIcon
                  ? ArDriveIcons.arrowLeftOutline()
                  : null,
              style: ArDriveButtonStyle.secondary,
              text: onBoarding.secundaryButtonText,
              onPressed: () => onBoarding.secundaryButtonAction(),
            ),
            const SizedBox(width: 32),
            ArDriveButton(
              iconAlignment: IconButtonAlignment.right,
              icon: ArDriveIcons.arrowRightOutline(
                color: Colors.white,
              ),
              text: onBoarding.primaryButtonText,
              onPressed: () => onBoarding.primaryButtonAction(),
            ),
          ],
        ),
      ],
    );
  }
}

class _OnBoarding {
  final String title;
  final String description;
  final String primaryButtonText;
  final String secundaryButtonText;
  final Function primaryButtonAction;
  final Function secundaryButtonAction;
  final bool secundaryButtonHasIcon;
  final ImageProvider illustration;

  _OnBoarding({
    required this.title,
    required this.description,
    required this.primaryButtonText,
    required this.secundaryButtonText,
    required this.illustration,
    required this.primaryButtonAction,
    required this.secundaryButtonAction,
    this.secundaryButtonHasIcon = true,
  });
}
