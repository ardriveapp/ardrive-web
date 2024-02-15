import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:responsive_builder/responsive_builder.dart';

import '../../../utils/app_localizations_wrapper.dart';
import '../../../utils/plausible_event_tracker/plausible_event_tracker.dart';
import '../../components/max_device_sizes_constrained_box.dart';

class TutorialsView extends StatefulWidget {
  const TutorialsView({
    super.key,
    required this.wallet,
  });
  final Wallet wallet;

  @override
  State<TutorialsView> createState() => TutorialsViewState();
}

class TutorialsViewState extends State<TutorialsView> {
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

  List<_TutorialPage> get _list => [
        _TutorialPage(
          nextButtonText: appLocalizationsOf(context).next,
          nextButtonAction: () {
            _goToNextPage();
          },
          title: appLocalizationsOf(context).onboarding1Title,
          description:
              'The permaweb is just like the currently existing web, but everything published on it is available forever - meaning that you will never risk losing a file ever again.',
          // secondaryButtonHasIcon: false,
          illustration: AssetImage(Resources.images.login.placeholder1),
        ),
        _TutorialPage(
          nextButtonText: appLocalizationsOf(context).next,
          nextButtonAction: () {
            _goToNextPage();
          },
          previousButtonText: appLocalizationsOf(context).backButtonOnboarding,
          previousButtonAction: () {
            _goToPreviousPage();
          },
          title: 'Complete Privacy Control',
          description:
              'When you upload content, you can choose to make it public or private. Private content is encrypted, and viewable only to you and those you share it with.',
          illustration: AssetImage(Resources.images.login.placeholder2),
        ),
        _TutorialPage(
          nextButtonText: appLocalizationsOf(context).diveInButtonOnboarding,
          nextButtonAction: () {
            context.read<LoginBloc>().add(
                  FinishOnboarding(
                    wallet: widget.wallet,
                  ),
                );
          },
          previousButtonText: appLocalizationsOf(context).backButtonOnboarding,
          previousButtonAction: () {
            _goToPreviousPage();
          },
          title: 'Pay-as-you-go Using a Credit Card',
          description:
              'When you upload a file, you will pay for it once and never again. You can access it forever without requiring a subscription, as with standard cloud storage.',
          illustration: AssetImage(Resources.images.login.placeholder1),
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
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return ScreenTypeLayout.builder(
      desktop: (context) => Material(
          color: colorTokens.containerL0,
          child: Expanded(
              child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                        top: BorderSide(
                            color: colorTokens.containerRed, width: 6)),
                    color: colorTokens.containerL0,
                  ),
                  padding: const EdgeInsets.fromLTRB(140, 100, 140, 100),
                  child: Expanded(
                      child: Center(
                          child: MaxDeviceSizesConstrainedBox(
                              maxHeightPercent: 1.0,
                              defaultMaxWidth: 1168,
                              defaultMaxHeight: 800,
                              child: _buildOnBoardingContent())))))),
      mobile: (context) => Scaffold(
        resizeToAvoidBottomInset: true,
        body: Container(
          color: colorTokens.containerL0,
          child: Align(
            child: MaxDeviceSizesConstrainedBox(
              child: Padding(
                padding: const EdgeInsets.all(80),
                child: _buildOnBoardingContent(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOnBoardingContent() {
    return _TutorialContent(
      key: ValueKey(_currentPage),
      tutorialPage: _list[_currentPage],
      pageNumber: _currentPage + 1,
      totalPages: _list.length,
    );
  }
}

class _TutorialContent extends StatelessWidget {
  final _TutorialPage tutorialPage;
  final int pageNumber;
  final int totalPages;

  const _TutorialContent({
    super.key,
    required this.tutorialPage,
    required this.pageNumber,
    required this.totalPages,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.desktop;

    return Container(
      color: colorTokens.containerL0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        // mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Text(
            tutorialPage.title,
            style: typography.display(
              color: colorTokens.textHigh,
              fontWeight: ArFontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            pageNumber == 1
                ? SizedBox(
                    width: 200,
                    child: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.fromLTRB(0, 0, 46, 0),
                        child: ArDriveImage(
                          image:
                              AssetImage(Resources.images.login.confettiLeft),
                          fit: BoxFit.contain,
                        )),
                  )
                : const SizedBox(width: 200),
            Expanded(
              child: Text(tutorialPage.description,
                  textAlign: TextAlign.center,
                  style: typography.heading5(
                    color: colorTokens.textLow,
                    fontWeight: ArFontWeight.semiBold,
                  )),
            ),
            pageNumber == 1
                ? SizedBox(
                    width: 200,
                    child: Container(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.fromLTRB(46, 0, 0, 0),
                        child: ArDriveImage(
                          image:
                              AssetImage(Resources.images.login.confettiLeft),
                          fit: BoxFit.contain,
                        )),
                  )
                : const SizedBox(width: 200),
          ]),
          const SizedBox(height: 60),
          Expanded(
            child: ArDriveImage(
              image: tutorialPage.illustration,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 56),
          Row(
            key: const ValueKey('buttons'),
            children: [
              Container(
                  alignment: Alignment.centerLeft,
                  width: 200,
                  child: (tutorialPage.previousButtonText != null &&
                          tutorialPage.previousButtonAction != null)
                      ? Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: tutorialPage.previousButtonText!,
                                style: typography.paragraphLarge(
                                    color: colorTokens.textLink,
                                    fontWeight: ArFontWeight.semiBold),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () =>
                                      tutorialPage.previousButtonAction!(),
                              ),
                            ],
                          ),
                        )
                      : null),
              Expanded(
                  child: Container(
                      alignment: Alignment.center,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: colorTokens.textXLow,
                          ),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          '$pageNumber/$totalPages',
                          style: typography.paragraphLarge(
                              color: colorTokens.textLow,
                              fontWeight: ArFontWeight.semiBold),
                        ),
                      ))),
              Container(
                  width: 200,
                  alignment: Alignment.centerRight,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: tutorialPage.nextButtonText,
                          style: typography.paragraphLarge(
                              color: colorTokens.textLink,
                              fontWeight: ArFontWeight.semiBold),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => tutorialPage.nextButtonAction(),
                        ),
                      ],
                    ),
                  ))
            ],
          ),
        ],
      ),
    );
  }
}

class _TutorialPage {
  final String title;
  final String description;
  final String nextButtonText;
  final Function nextButtonAction;
  final String? previousButtonText;
  final Function? previousButtonAction;
  // final bool secondaryButtonHasIcon;
  final ImageProvider illustration;

  _TutorialPage({
    required this.title,
    required this.description,
    required this.nextButtonText,
    required this.nextButtonAction,
    required this.illustration,
    this.previousButtonText,
    this.previousButtonAction,
    // required this.illustration,
    // this.secondaryButtonHasIcon = true,
  });
}
