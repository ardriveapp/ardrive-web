import 'dart:math';

import 'package:ardrive/authentication/components/breakpoint_layout_builder.dart';
import 'package:ardrive/authentication/components/dot_pattern_painter.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/misc/misc.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../../utils/app_localizations_wrapper.dart';
import '../../../utils/plausible_event_tracker/plausible_event_tracker.dart';

class TutorialsView extends StatefulWidget {
  const TutorialsView(
      {super.key,
      required this.wallet,
      this.mnemonic,
      required this.showWalletCreated});
  final Wallet wallet;
  final String? mnemonic;
  final bool showWalletCreated;

  @override
  State<TutorialsView> createState() => TutorialsViewState();
}

class TutorialsViewState extends State<TutorialsView> {
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();

    PlausibleEventTracker.trackPageview(page: PlausiblePageView.tutorialsPage1);
  }

  List<_TutorialPage> get _list => [
        _TutorialPage(
          nextButtonText: appLocalizationsOf(context).next,
          nextButtonAction: () {
            PlausibleEventTracker.trackClickTutorialNextButton(
              PlausiblePageView.tutorialsPage1,
            );

            _goToNextPage();
          },
          title: appLocalizationsOf(context).onboarding1Title,
          description:
              'The permaweb is just like the currently existing web, but everything published on it is available forever - meaning that you will never risk losing a file ever again.',
          // secondaryButtonHasIcon: false,
          videoUrl:
              'https://arweave.net/KynB0c5IBqk66gO2E6W9lqD92sfxZXIuiWT08cmwWzc',
        ),
        _TutorialPage(
          nextButtonText: appLocalizationsOf(context).next,
          nextButtonAction: () {
            PlausibleEventTracker.trackClickTutorialNextButton(
              PlausiblePageView.tutorialsPage2,
            );

            _goToNextPage();
          },
          previousButtonText: appLocalizationsOf(context).backButtonOnboarding,
          previousButtonAction: () {
            PlausibleEventTracker.trackClickTutorialBackButton(
              PlausiblePageView.tutorialsPage2,
            );
            _goToPreviousPage();
          },
          title: 'Complete Privacy Control',
          description:
              'When you upload content, you can choose to make it public or private. Private content is encrypted, and viewable only to you and those you share it with.',
          videoUrl:
              'https://arweave.net/IDxtPlhnBBdXSOSeIwSjFlywc18ZZ2p-QMxtaPT3pZs',
        ),
        _TutorialPage(
          nextButtonText:
              widget.showWalletCreated ? 'Get your wallet' : 'Go to app',
          nextButtonAction: () {
            if (widget.showWalletCreated) {
              PlausibleEventTracker.trackClickTutorialGetYourWallet();

              context.read<LoginBloc>().add(
                    CompleteWalletGeneration(
                      wallet: widget.wallet,
                      mnemonic: widget.mnemonic,
                    ),
                  );
            } else {
              PlausibleEventTracker.trackClickTutorialGoToAppLink();

              context.read<LoginBloc>().add(
                    FinishOnboarding(
                      wallet: widget.wallet,
                    ),
                  );
            }
          },
          previousButtonText: appLocalizationsOf(context).backButtonOnboarding,
          previousButtonAction: () {
            PlausibleEventTracker.trackClickTutorialBackButton(
              PlausiblePageView.tutorialsPage3,
            );
            _goToPreviousPage();
          },
          title: 'Pay-as-you-go Using a Credit Card',
          description:
              'When you upload a file, you will pay for it once and never again. You can access it forever without requiring a subscription, as with standard cloud storage.',
          videoUrl:
              'https://arweave.net/vhrQJSssEMi2UWx8W6BDijZxT82u2qD_BamI_1NmgRw',
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

    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;
    final phoneLayout = width < TABLET;

    final containerHeight = height - 6;

    final isDarkMode = ArDriveTheme.of(context).themeData.name == 'dark';
    final List<Color> radialColors = isDarkMode
        ? [
            const Color(0x66d9d9d9),
            const Color(0x00d9d9d9),
          ]
        : [
            const Color(0x11d9d9d9),
            const Color(0x00d9d9d9),
          ];

    return Material(
      color: colorTokens.containerL0,
      child: Container(
          decoration: BoxDecoration(
              border: Border(
                  top: BorderSide(color: colorTokens.containerRed, width: 6))),
          child: SizedBox.expand(
            child: Stack(children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SizedBox(
                    height: 264,
                    child: ShaderMask(
                      shaderCallback: (Rect bounds) {
                        return RadialGradient(
                          center: Alignment.topCenter,
                          radius: 2.5,
                          colors: radialColors,
                          tileMode: TileMode.clamp,
                        ).createShader(bounds);
                      },
                      child: ClipRect(
                        child: CustomPaint(
                          painter: DotPatternPainter(
                              dotColor: colorTokens.strokeLow),
                        ),
                      ),
                    )),
              ),
              Center(
                  child: SingleChildScrollView(
                      child: Center(
                child: Container(
                    height: containerHeight - 64,
                    constraints: const BoxConstraints(maxWidth: 1164),
                    child: Container(
                      padding: phoneLayout
                          ? const EdgeInsets.all(32)
                          : const EdgeInsets.fromLTRB(32, 20, 32, 20),
                      child: _buildOnBoardingContent(phoneLayout),
                    )),
              ))),
            ]),
          )),
    );
  }

  Widget _buildOnBoardingContent(bool phoneLayout) {
    return _TutorialContent(
      key: ValueKey(_currentPage),
      tutorialPage: _list[_currentPage],
      pageNumber: _currentPage + 1,
      totalPages: _list.length,
      phoneLayout: phoneLayout,
    );
  }
}

class _TutorialContent extends StatefulWidget {
  final _TutorialPage tutorialPage;
  final int pageNumber;
  final int totalPages;
  final bool phoneLayout;

  const _TutorialContent({
    super.key,
    required this.tutorialPage,
    required this.pageNumber,
    required this.totalPages,
    required this.phoneLayout,
  });

  @override
  State<_TutorialContent> createState() => _TutorialContentState();
}

class _TutorialContentState extends State<_TutorialContent> {
  late VideoPlayerController _videoPlayerController;

  bool _loadingVideo = true;

  @override
  void initState() {
    super.initState();
    _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(widget.tutorialPage.videoUrl),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    _videoPlayerController.setLooping(true);
    _videoPlayerController.initialize().then((_) {
      if (mounted) {
        setState(() {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              // mutes the video
              _videoPlayerController.setVolume(0);
              // Plays the video once the widget is build and loaded.
              _videoPlayerController.play();
              setState(() {
                _loadingVideo = false;
              });
            }
          });
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    final phoneLayout = MediaQuery.of(context).size.width < TABLET;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.phoneLayout) ...[
          const Expanded(child: SizedBox()),
          ArDriveImage(
            image: AssetImage(Resources.images.login.confetti),
          )
        ],
        Text(
          widget.tutorialPage.title,
          textAlign: TextAlign.center,
          style: typography.display(
            color: colorTokens.textHigh,
            fontWeight: ArFontWeight.bold,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            widget.pageNumber == 1 && !widget.phoneLayout
                ? SizedBox(
                    width: 160,
                    child: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.fromLTRB(0, 0, 46, 0),
                      child: ArDriveImage(
                        image: AssetImage(Resources.images.login.confettiLeft),
                        fit: BoxFit.contain,
                      ),
                    ),
                  )
                : SizedBox(
                    width: widget.phoneLayout ? 0 : 160,
                  ),
            Expanded(
              child: Text(
                widget.tutorialPage.description,
                textAlign: TextAlign.center,
                style: typography.heading5(
                  color: colorTokens.textLow,
                  fontWeight: ArFontWeight.semiBold,
                ),
              ),
            ),
            widget.pageNumber == 1 && !widget.phoneLayout
                ? SizedBox(
                    width: 160,
                    child: Container(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.fromLTRB(46, 0, 0, 0),
                        child: ArDriveImage(
                          image:
                              AssetImage(Resources.images.login.confettiRight),
                          fit: BoxFit.contain,
                        )),
                  )
                : SizedBox(width: widget.phoneLayout ? 0 : 160),
          ],
        ),
        phoneLayout
            ? Expanded(
                child: Column(children: [
                  const SizedBox(height: 20),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: colorTokens.buttonSecondaryHover,
                        ),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        '${widget.pageNumber}/${widget.totalPages}',
                        style: typography.paragraphLarge(
                            color: colorTokens.textLow,
                            fontWeight: ArFontWeight.semiBold),
                      ),
                    ),
                  ),
                  const Expanded(child: SizedBox())
                ]),
              )
            : Flexible(
                child: Center(
                  child: _loadingVideo
                      ? const Center(
                          child: CircularProgressIndicator(),
                        )
                      : Container(
                          padding: const EdgeInsets.all(1),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: colorTokens.strokeLow,
                              width: 1,
                            ),
                          ),
                          child: AspectRatio(
                            aspectRatio: 4196 / 2160,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: VideoPlayer(
                                _videoPlayerController,
                              ),
                            ),
                          ),
                        ),
                ),
              ),
        Row(
          key: const ValueKey('buttons'),
          children: [
            Expanded(
              child: Container(
                  alignment: Alignment.centerLeft,
                  child: (widget.tutorialPage.previousButtonText != null &&
                          widget.tutorialPage.previousButtonAction != null)
                      ? Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: widget.tutorialPage.previousButtonText!,
                                style: typography.heading5(
                                    color: colorTokens.textLink,
                                    fontWeight: ArFontWeight.semiBold),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () => widget
                                      .tutorialPage.previousButtonAction!(),
                              ),
                            ],
                          ),
                        )
                      : null),
            ),
            phoneLayout
                ? const SizedBox()
                : Container(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: colorTokens.buttonSecondaryHover,
                      ),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      '${widget.pageNumber}/${widget.totalPages}',
                      style: typography.paragraphLarge(
                          color: colorTokens.textLow,
                          fontWeight: ArFontWeight.semiBold),
                    ),
                  ),
            Expanded(
              child: Container(
                  alignment: Alignment.centerRight,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: widget.tutorialPage.nextButtonText,
                          style: typography.heading5(
                              color: colorTokens.textLink,
                              fontWeight: ArFontWeight.semiBold),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () {
                              widget.tutorialPage.nextButtonAction();
                            },
                        ),
                      ],
                    ),
                  )),
            )
          ],
        ),
      ],
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
  final String videoUrl;

  _TutorialPage({
    required this.title,
    required this.description,
    required this.nextButtonText,
    required this.nextButtonAction,
    required this.videoUrl,
    this.previousButtonText,
    this.previousButtonAction,
    // this.secondaryButtonHasIcon = true,
  });
}
