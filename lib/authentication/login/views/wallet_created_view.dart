// ignore_for_file: deprecated_member_use

import 'dart:ui';

import 'package:ardrive/authentication/components/breakpoint_layout_builder.dart';
import 'package:ardrive/authentication/components/login_card_new.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/utils/io_utils.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';

class WalletCreatedView extends StatefulWidget {
  const WalletCreatedView({super.key, this.mnemonic, required this.wallet});

  final String? mnemonic;
  final Wallet wallet;

  @override
  State<WalletCreatedView> createState() => _WalletCreatedViewState();
}

class _PageInfo {
  String title;
  String description;

  _PageInfo({required this.title, required this.description});
}

class _WalletCreatedViewState extends State<WalletCreatedView> {
  bool _isTermsChecked = false;
  bool _isBlurred = true;
  bool _showCheck = false;
  bool _showCheckSmallIcon = false;

  late int _currentPage;

  final _pageInfo = [
    _PageInfo(
        title: 'What is a Seed Phrase?',
        description:
            "A seed phrase is a unique set of words acting as your wallet's master key. It generates your wallet whenever you log in. You can store it in a password manager or secure offline location for added protection."),
    _PageInfo(
        title: 'What is a Keyfile?',
        description:
            'A keyfile is another way to access your wallet. It contains encrypted information that helps us authenticate your identity. Keep it secure alongside your seed phrase.'),
    _PageInfo(
        title: 'About security',
        description:
            "It's crucial to safeguard both your seed phrase and keyfile. Losing them means permanent loss of access to your funds as we don't retain your wallet.")
  ];

  @override
  void initState() {
    super.initState();

    _currentPage = widget.mnemonic != null ? 0 : 1;

    PlausibleEventTracker.trackPageview(
      page: PlausiblePageView.walletCreatedPage,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    final seedPhraseCard = LoginCardNew(
      child: Column(
        children: [
          Container(
            color: colorTokens.containerL3,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(children: [
                if (widget.mnemonic != null) ...[
                  _tabLink(
                    'Seed phrase',
                    0,
                    rightIcon: SvgPicture.asset(
                      Resources.images.icons.encryptedLock,
                      width: 20,
                      height: 20,
                      color: _currentPage == 0
                          ? colorTokens.textHigh
                          : colorTokens.textLow,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Spacer()
                ],
                _tabLink('Keyfile', 1),
                const SizedBox(width: 16),
                _tabLink('Security', 2)
              ]),
            ),
          ),
          _currentPage == 0
              ? SizedBox(
                  width: 450,
                  height: 281,
                  child: Stack(fit: StackFit.expand, children: [
                    _blurred(450, widget.mnemonic!, _isBlurred),
                    Positioned(
                        right: 46,
                        bottom: 16,
                        child: _iconButton(
                            _isBlurred
                                ? Resources.images.icons.eyeClosed
                                : Resources.images.icons.eyeOpen, () {
                          setState(() {
                            _isBlurred = !_isBlurred;
                          });
                        })),
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _showCheckSmallIcon
                            ? ArDriveImage(
                                width: 20,
                                height: 20,
                                image: AssetImage(
                                    Resources.images.login.checkCircle),
                                fit: BoxFit.contain)
                            : ArDriveClickArea(
                                child: GestureDetector(
                                onTap: () => _copy(true),
                                child: SvgPicture.asset(
                                  Resources.images.icons.copy,
                                  width: 20,
                                  height: 20,
                                  color: colorTokens.textMid,
                                ),
                              )),
                      ),
                    )
                  ]))
              : _currentPage == 1
                  ? ArDriveImage(
                      image: AssetImage(Resources.images.login.whatIsAKeyfile),
                      fit: BoxFit.contain)
                  : ArDriveImage(
                      image: AssetImage(Resources.images.login.aboutSecurity),
                      fit: BoxFit.contain),
          Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_pageInfo[_currentPage].title,
                      style: typography.paragraphNormal()),
                  const SizedBox(height: 12),
                  Text(_pageInfo[_currentPage].description,
                      style: typography.paragraphNormal(
                          color: colorTokens.textLow,
                          fontWeight: ArFontWeight.semiBold)),
                ],
              ))
        ],
      ),
    );

    late EdgeInsets padding;

    final width = MediaQuery.of(context).size.width;
    if (width < TABLET) {
      padding = const EdgeInsets.fromLTRB(24, 64, 24, 64);
    } else {
      padding = const EdgeInsets.fromLTRB(56, 64, 56, 64);
    }

    final downloadWalletCard = LoginCardNew(
        child: Padding(
      padding: padding,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
              child: ArDriveImage(
            image: AssetImage(Resources.images.login.checkCircle),
            height: 32,
          )),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.topCenter,
            child: Text(
              // FIXME: Add localization key
              'Wallet Created',
              style: typography.heading2(
                  color: colorTokens.textHigh, fontWeight: ArFontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Please store your seedphrase and download your keyfile to secure locations to continue. If you log out, you will need at least one of these to log back in.',
            style: ArDriveTypographyNew.of(context).paragraphNormal(
              color: colorTokens.textLow,
              fontWeight: ArFontWeight.semiBold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          if (widget.mnemonic != null) ...[
            ArDriveButtonNew(
              typography: typography,
              text: 'Copy Seed Phrase',
              variant: ButtonVariant.outline,
              onPressed: () {
                PlausibleEventTracker.trackClickCopySeedPhraseButton();
                _copy(false);
              },
              rightIcon: IgnorePointer(
                  child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _showCheck
                    ? ArDriveImage(
                        width: 20,
                        height: 20,
                        image: AssetImage(Resources.images.login.checkCircle),
                        fit: BoxFit.contain)
                    : SvgPicture.asset(
                        Resources.images.icons.copy,
                        width: 20,
                        height: 20,
                        color: colorTokens.textMid,
                      ),
              )),
            ),
            const SizedBox(height: 12),
          ],
          ArDriveButtonNew(
            typography: typography,
            text: 'Download Keyfile',
            variant: ButtonVariant.outline,
            onPressed: () async {
              final ioUtils = ArDriveIOUtils();

              PlausibleEventTracker.trackClickDownloadKeyfileButton();

              final success = await ioUtils.downloadWalletAsJsonFile(
                wallet: widget.wallet,
              );
              if (success && AppPlatform.isAndroid) {
                showArDriveDialog(
                  // ignore: use_build_context_synchronously
                  context,
                  content: ArDriveStandardModalNew(
                    title: 'Download Successful',
                    description:
                        'Your wallet keyfile has been downloaded successfully. You can find it in your Downloads folder.',
                    actions: [
                      ModalAction(
                        title: 'OK',
                        action: () {
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
                  ),
                );
              }
            },
            rightIcon: IgnorePointer(
                child: SvgPicture.asset(
              Resources.images.icons.download,
              width: 20,
              height: 20,
              color: colorTokens.textMid,
            )),
          ),
          const SizedBox(height: 40),
          ArDriveButtonNew(
            typography: typography,
            text: _isTermsChecked ? 'Go to App' : 'Check to Continue',
            isDisabled: !_isTermsChecked,
            variant: ButtonVariant.primary,
            onPressed: () async {
              PlausibleEventTracker.trackClickGoToAppButton();

              context.read<LoginBloc>().add(
                    FinishOnboarding(
                      wallet: widget.wallet,
                    ),
                  );
            },
          ),
          const SizedBox(height: 12),
          Row(children: [
            Checkbox(
              fillColor: MaterialStateProperty.all(Colors.transparent),
              checkColor: colorTokens.textLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(2.0),
              ),
              side: MaterialStateBorderSide.resolveWith((states) =>
                  BorderSide(width: 1.0, color: colorTokens.textLow)),
              value: _isTermsChecked,
              onChanged: ((value) {
                if (value ?? false) {
                  PlausibleEventTracker.trackClickBackedUpSeedPhraseCheckBox();
                }
                setState(() => _isTermsChecked = value ?? false);
              }),
            ),
            Expanded(
                child: Text('I have safely backed-up a copy of my wallet.',
                    maxLines: 2,
                    style: typography.paragraphNormal(
                        color: colorTokens.textLow,
                        fontWeight: ArFontWeight.semiBold)))
          ]),
        ],
      ),
    ));
    return BreakpointLayoutBuilder(
      largeDesktop: (context) => Material(
          color: colorTokens.containerL0,
          child: SizedBox.expand(
            child: Center(
              child: SingleChildScrollView(
                child: Container(
                    color: colorTokens.containerL0,
                    alignment: Alignment.center,
                    child: Center(
                        child: IntrinsicHeight(
                            child: Row(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        seedPhraseCard,
                        const SizedBox(width: 24),
                        downloadWalletCard,
                      ],
                    )))),
              ),
            ),
          )),
      tablet: (context) => Scaffold(
          resizeToAvoidBottomInset: true,
          body: SingleChildScrollView(
              child: Container(
                  padding: const EdgeInsets.all(24),
                  color: colorTokens.containerL0,
                  alignment: Alignment.center,
                  child: Center(
                      child: IntrinsicWidth(
                          child: Column(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      downloadWalletCard,
                      const SizedBox(height: 24),
                      seedPhraseCard,
                    ],
                  )))))),
      phone: (context) => Scaffold(
          resizeToAvoidBottomInset: true,
          body: SingleChildScrollView(
              child: Container(
                  padding: const EdgeInsets.all(24),
                  color: colorTokens.containerL0,
                  alignment: Alignment.center,
                  child: Center(
                      child: IntrinsicWidth(
                          child: Column(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      downloadWalletCard,
                      const SizedBox(height: 24),
                      seedPhraseCard,
                    ],
                  )))))),
    );
  }

  Widget _blurred(double width, String seedPhrase, bool isBlurred) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    var text = Container(
        width: width,
        // height: 45,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colorTokens.containerL1,
        ),
        // alignment: Alignment.centerLeft,
        padding: const EdgeInsets.all(24),
        child: Text(seedPhrase,
            style: typography.paragraphNormal(
                color: colorTokens.textMid, fontWeight: ArFontWeight.book)));

    return isBlurred
        ? ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: text,
          )
        : text;
  }

  Widget _tabLink(String text, int index, {Widget? rightIcon}) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    final textRow = Row(
      children: [
        Text(text,
            style: typography.paragraphLarge(
                color: (index == _currentPage)
                    ? colorTokens.textHigh
                    : colorTokens.textLow,
                fontWeight: ArFontWeight.semiBold)),
        if (rightIcon != null) ...[const SizedBox(width: 6), rightIcon]
      ],
    );

    return index == _currentPage
        ? textRow
        : ArDriveClickArea(
            child: GestureDetector(
            onTap: () {
              setState(() => _currentPage = index);
            },
            child: textRow,
          ));
  }

  Widget _iconButton(String resource, void Function() callback) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return ArDriveClickArea(
        child: GestureDetector(
            onTap: callback,
            child: SvgPicture.asset(resource,
                width: 20, height: 20, color: colorTokens.textMid)));
  }

  void _copy(bool smallIcon) {
    if (widget.mnemonic == null) {
      return;
    }
    Clipboard.setData(ClipboardData(text: widget.mnemonic!));
    if (mounted) {
      if (smallIcon ? _showCheckSmallIcon : _showCheck) {
        return;
      }

      setState(() {
        if (smallIcon) {
          _showCheckSmallIcon = true;
        } else {
          _showCheck = true;
        }

        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) {
            return;
          }

          setState(() {
            if (smallIcon) {
              _showCheckSmallIcon = false;
            } else {
              _showCheck = false;
            }
          });
        });
      });
    }
  }
}
