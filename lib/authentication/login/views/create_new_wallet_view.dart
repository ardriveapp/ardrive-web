import 'dart:async';
import 'dart:ui';

import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/authentication/login/blocs/stub_web_wallet.dart' // stub implementation
    if (dart.library.html) 'package:ardrive/authentication/login/blocs/web_wallet.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/arweave.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'accent_painter.dart';
import 'login_copy_button.dart';

class CreateNewWalletView extends StatefulWidget {
  const CreateNewWalletView({super.key, required this.mnemonic});

  final String mnemonic;

  @override
  State<CreateNewWalletView> createState() => CreateNewWalletViewState();
}

class WordOption {
  WordOption(this.word, this.index);

  int index;
  String word;
}

class CreateNewWalletViewState extends State<CreateNewWalletView> {
  int _currentPage = 0;
  bool _isBlurredSeedPhrase = true;
  late final List<String> _mnemonicWords;

  final Completer<Wallet> preGeneratedWallet = Completer();

  List<WordOption> _wordsToCheck = [];
  List<WordOption> _wordOptions = [];
  bool _wordsAreCorrect = false;

  @override
  void initState() {
    super.initState();
    _mnemonicWords = widget.mnemonic.split(' ');
    _resetMemoryCheckItems();
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      var wallet = await generateWalletFromMnemonic(widget.mnemonic);
      preGeneratedWallet.complete(wallet);
    });
  }

  void goNextPage() async {
    if (_currentPage == 2) {
      context
          .read<LoginBloc>()
          .add(AddWalletFromCompleter(widget.mnemonic, preGeneratedWallet));
    } else {
      setState(() {
        _isBlurredSeedPhrase = true;
        _wordsAreCorrect = false;
        _currentPage++;
      });
      _trackPlausible();
    }
  }

  void goPrevPage() {
    setState(() {
      _isBlurredSeedPhrase = true;
      _wordsAreCorrect = false;
    });
    if (_currentPage == 0) {
      context.read<LoginBloc>().add(const ForgetWallet());
    } else {
      setState(() {
        _currentPage--;
      });
      _trackPlausible();
    }
  }

  void _trackPlausible() {
    switch (_currentPage) {
      case 1:
        PlausibleEventTracker.trackPageview(
          page: PlausiblePageView.writeDownSeedPhrasePage,
        );
        break;
      case 2:
        PlausibleEventTracker.trackPageview(
          page: PlausiblePageView.verifySeedPhrasePage,
        );
        break;
    }
  }

  void _resetMemoryCheckItems() {
    final indices = List<int>.generate(_mnemonicWords.length, (i) => i);
    indices.shuffle();

    _wordsToCheck = indices
        .sublist(0, 4)
        .map(
          (e) => WordOption('', e),
        )
        .toList();

    _wordOptions = _wordsToCheck
        .map((e) => WordOption(_mnemonicWords[e.index], -1))
        .toList();

    var wordSet = _wordOptions.map((e) => e.word).toSet();

    var optionsIndex = 4;
    while (optionsIndex < 8) {
      for (var randWord in bip39.generateMnemonic().split(' ')) {
        if (!wordSet.contains(randWord)) {
          _wordOptions.add(WordOption(randWord, -1));
          wordSet.add(randWord);
          optionsIndex++;
          if (optionsIndex >= 8) {
            break;
          }
        }
      }
    }

    _wordOptions.shuffle();
  }

  List<Widget> createRows(
      {required List<Widget> items,
      required int rowCount,
      required double hGap,
      required double vGap}) {
    List<Widget> rows = [];

    int count = 0;

    while (count < items.length) {
      List<Widget> rowItems = [];
      for (int i = 0; i < rowCount; i++) {
        if (count < items.length) {
          if (i % rowCount != 0) {
            rowItems.add(SizedBox(width: hGap));
          }
          rowItems.add(items[count]);
          count++;
        }
      }
      if (count > rowCount) {
        rows.add(SizedBox(height: vGap));
      }
      rows.add(Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: rowItems,
      ));
    }
    return rows;
  }

  Widget _buildContent(BuildContext context) {
    Widget view;

    switch (_currentPage) {
      case 2:
        view = _buildConfirmYourSeedPhrase();
        break;
      case 1:
        view = _buildWriteDownSeedPhrase();
        break;
      default:
        view = _buildGettingStarted();
    }

    return view;
  }

  Widget _backButton() {
    var colors = ArDriveTheme.of(context).themeData.colors;
    return Expanded(
        child: Container(
            decoration: BoxDecoration(
                border: Border(
                    top: BorderSide(
                        color: colors.themeBorderDefault, width: 1))),
            child: TextButton(
              style: ButtonStyle(
                overlayColor: MaterialStateProperty.resolveWith<Color?>(
                    (Set<MaterialState> states) {
                  return colors.themeFgDefault.withOpacity(0.1);
                }),
              ),
              onPressed: goPrevPage,
              child: Center(
                  // TODO: create/update localization key
                  child: Text('Back',
                      style: ArDriveTypography.body
                          .smallBold700(color: colors.themeFgDefault))),
            )));
  }

  Widget _nextButton({required String text, required bool isDisabled}) {
    return Expanded(
        child: ArDriveButton(
            isDisabled: isDisabled,
            iconAlignment: IconButtonAlignment.right,
            icon: Container(
                padding: const EdgeInsets.only(top: 4),
                child: Icon(Icons.arrow_forward,
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeFgOnAccent,
                    size: 20)),
            fontStyle: ArDriveTypography.body.smallBold700(
                color:
                    ArDriveTheme.of(context).themeData.colors.themeFgOnAccent),
            maxWidth: double.maxFinite,
            borderRadius: 0,
            text: text,
            onPressed: goNextPage));
  }

  Widget _buildCard(List<String> cardInfo) {
    final screenSize = MediaQuery.of(context).size;

    final wideScreen = screenSize.width > (374 * 2 + 24 * 3);
    final containerWidth = wideScreen ? 374.0 : screenSize.width - 40.0;
    final height = wideScreen ? 180.0 : null;

    return Stack(
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              padding: const EdgeInsets.only(left: 35),
              child: Text(
                cardInfo[0],
                style: ArDriveTypography.headline.headline5Regular(),
              )),
          const SizedBox(height: 16),
          Container(
            width: containerWidth,
            height: height,
            padding: const EdgeInsets.fromLTRB(30, 24, 30, 24),
            decoration: BoxDecoration(
              color: ArDriveTheme.of(context).themeData.colors.themeBgSurface,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              cardInfo[1],
              style: ArDriveTypography.body
                  .bodyRegular()
                  .copyWith(fontSize: 16, height: 1.4),
            ),
          )
        ]),
        Container(
          margin: const EdgeInsets.fromLTRB(15, 5, 0, 0),
          width: 5,
          height: 20,
          child: CustomPaint(
            painter: AccentPainter(lineHeight: 83),
          ),
        ),
      ],
    );
  }

  Widget blurred(double width, String word, bool isBlurred) {
    var radius = const Radius.circular(4);

    final colors = ArDriveTheme.of(context).themeData.colors;
    final isDarkMode = ArDriveTheme.of(context).themeData.name == 'dark';

    var text = Container(
        width: width,
        height: 45,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
            color: isDarkMode ? colors.themeBgSurface : colors.themeBgSubtle,
            borderRadius:
                BorderRadius.only(topRight: radius, bottomRight: radius)),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 16),
        child: Text(word,
            style:
                ArDriveTypography.body.smallBold(color: colors.themeFgMuted)));

    return isBlurred
        ? ClipRect(
            child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: text,
          ))
        : text;
  }

  Widget _buildSeedPhraseWord(int num, String word) {
    final screenSize = MediaQuery.of(context).size;
    final width = screenSize.width > (176 * 3 + 24 * 4)
        ? 176.0
        : (screenSize.width - 24 * 3) / 2;
    var radius = const Radius.circular(4);
    var colors = ArDriveTheme.of(context).themeData.colors;
    final isDarkMode = ArDriveTheme.of(context).themeData.name == 'dark';

    return SizedBox(
        width: width,
        height: 45,
        child: Row(
          children: [
            Container(
                width: 22,
                height: 45,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color:
                        isDarkMode ? colors.themeBgCanvas : colors.themeGbMuted,
                    borderRadius:
                        BorderRadius.only(topLeft: radius, bottomLeft: radius)),
                child: Center(
                    child: Text(
                  '$num',
                  style: ArDriveTypography.body
                      .smallBold700(color: colors.themeFgDefault),
                ))),
            blurred(width - 22, word, _isBlurredSeedPhrase),
          ],
        ));
  }

  Widget _buildWordToCheck(double width, WordOption wordOption) {
    var radius = const Radius.circular(2);
    var colors = ArDriveTheme.of(context).themeData.colors;

    var currentWordToCheckIndex =
        _wordsToCheck.indexWhere((e) => e.word.isEmpty);
    var showCursor = (currentWordToCheckIndex >= 0 &&
        wordOption == _wordsToCheck[currentWordToCheckIndex]);

    final isDarkMode = ArDriveTheme.of(context).themeData.name == 'dark';

    var borderColor = showCursor
        ? colors.themeFgDefault
        : isDarkMode
            ? colors.themeBgCanvas
            : colors.themeBgSubtle;
    var numberColor =
        showCursor ? colors.themeBgSurface : colors.themeFgDefault;

    return Container(
        width: width,
        height: 45,
        decoration: BoxDecoration(
            color: borderColor, borderRadius: BorderRadius.circular(4)),
        child: Row(
          children: [
            Container(
                width: 22,
                height: 45,
                alignment: Alignment.center,
                child: Center(
                    child: Text('${wordOption.index + 1}',
                        style: ArDriveTypography.body
                            .smallBold700(color: numberColor)))),
            Stack(
                alignment:
                    showCursor ? Alignment.centerLeft : Alignment.centerRight,
                children: [
                  Container(
                      width: width - 23,
                      height: 43,
                      decoration: BoxDecoration(
                          color: colors.themeBgSurface,
                          borderRadius: BorderRadius.only(
                              topRight: radius, bottomRight: radius)),
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 16),
                      child: Text(wordOption.word,
                          style: ArDriveTypography.body
                              .smallBold700(color: colors.themeFgDefault))),
                  if (wordOption.word.isNotEmpty)
                    IconButton.filled(
                        onPressed: () {
                          setState(() {
                            for (var element in _wordOptions) {
                              if (element.word == wordOption.word) {
                                element.index = -1;
                              }
                            }
                            wordOption.word = '';
                          });
                        },
                        icon: Icon(
                          Icons.highlight_off,
                          size: 16,
                          color: colors.themeFgDefault,
                        )),
                ])
          ],
        ));
  }

  Widget _buildConfirmSeedPhraseWordOption(
      double width, WordOption wordOption) {
    var radius = const Radius.circular(4);
    var selected = wordOption.index >= 0;
    var colors = ArDriveTheme.of(context).themeData.colors;
    final isDarkMode = ArDriveTheme.of(context).themeData.name == 'dark';

    var currentWordToCheckIndex =
        _wordsToCheck.indexWhere((e) => e.word.isEmpty);

    return selected
        ? SizedBox(
            width: width,
            height: 45,
            child: Row(
              children: [
                Container(
                    width: 22,
                    height: 45,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: colors.themeAccentBrand,
                        borderRadius: BorderRadius.only(
                            topLeft: radius, bottomLeft: radius)),
                    child: Center(
                        child: Text('${wordOption.index + 1}',
                            style: ArDriveTypography.body
                                .smallBold700(color: colors.themeFgOnAccent)))),
                Container(
                    width: width - 22,
                    height: 45,
                    decoration: BoxDecoration(
                        color: colors.themeFgDefault,
                        borderRadius: BorderRadius.only(
                            topRight: radius, bottomRight: radius)),
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 16),
                    child: Text(wordOption.word,
                        style: ArDriveTypography.body
                            .smallBold700(color: colors.themeBgSurface)))
              ],
            ))
        : MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
                onTap: () {
                  if (currentWordToCheckIndex == 3) {
                    var wordToCheck = _wordsToCheck[currentWordToCheckIndex];
                    wordToCheck.word = wordOption.word;
                    wordOption.index = wordToCheck.index;

                    if (_wordsToCheck.every((element) =>
                        _mnemonicWords[element.index] == element.word)) {
                      setState(() {
                        _wordsAreCorrect = true;
                      });
                    } else {
                      setState(() {
                        _resetMemoryCheckItems();
                        var snackBar = SnackBar(
                          width: 380,
                          content: Row(children: [
                            MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: GestureDetector(
                                  onTap: () {
                                    ScaffoldMessenger.of(context)
                                        .hideCurrentSnackBar();
                                  },
                                  child: Icon(Icons.close,
                                      size: 20, color: colors.themeErrorMuted),
                                )),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(
                                    // TODO: create/update localization key
                                    'Order of phrases is not correct. Please try again.',
                                    style: ArDriveTypography.body
                                        .smallBold(
                                          color: colors.themeErrorMuted,
                                        )
                                        .copyWith(fontSize: 14)))
                          ]),
                          shape: RoundedRectangleBorder(
                            side: BorderSide(
                                color: colors.themeErrorMuted, width: 1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          showCloseIcon: false,
                          backgroundColor: colors.themeErrorSubtle,
                          closeIconColor: colors.themeErrorMuted,
                          behavior: SnackBarBehavior.floating,
                        );

                        ScaffoldMessenger.of(context).showSnackBar(snackBar);
                      });
                    }
                  } else {
                    setState(() {
                      var wordToCheck = _wordsToCheck[currentWordToCheckIndex];
                      wordToCheck.word = wordOption.word;
                      wordOption.index = wordToCheck.index;
                    });
                  }
                },
                child: Container(
                    width: width,
                    height: 45,
                    padding: const EdgeInsets.only(left: 16),
                    decoration: BoxDecoration(
                        color: isDarkMode
                            ? colors.themeBgSurface
                            : colors.themeBgSubtle,
                        borderRadius: BorderRadius.circular(4)),
                    alignment: Alignment.centerLeft,
                    child: Text(wordOption.word,
                        style: ArDriveTypography.body
                            .smallBold700(color: colors.themeFgDefault)))));
  }

  Widget _buildWriteDownSeedPhrase() {
    final screenSize = MediaQuery.of(context).size;

    final rowCount = screenSize.width > (176 * 3 + 24 * 4) ? 3 : 2;
    final topBottomPadding = rowCount == 2 ? 40.0 : 0.0;

    var rows = Column(
        children: createRows(
            items: _mnemonicWords
                .asMap()
                .map((i, e) => MapEntry(i, _buildSeedPhraseWord(i + 1, e)))
                .values
                .toList(),
            rowCount: rowCount,
            hGap: 24,
            vGap: 24));

    return Scaffold(
      body: Center(
        child: ArDriveScrollBar(
          alwaysVisible: true,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
                top: topBottomPadding, bottom: topBottomPadding),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  // TODO: create/update localization key
                  'Write Down Seed Phrase',
                  textAlign: TextAlign.center,
                  style: ArDriveTypography.headline
                      .headline4Regular(
                          color: ArDriveTheme.of(context)
                              .themeData
                              .colors
                              .themeFgDefault)
                      .copyWith(fontSize: 32),
                ),
                const SizedBox(height: 8),
                Container(
                    constraints: const BoxConstraints(maxWidth: 508),
                    child: Text(
                      // TODO: create/update localization key
                      'Please carefully write down your seed phrase, in this order, and keep it somewhere safe.',
                      textAlign: TextAlign.center,
                      style: ArDriveTypography.body.smallBold(
                          color: ArDriveTheme.of(context)
                              .themeData
                              .colors
                              .themeFgSubtle),
                    )),
                const SizedBox(height: 72),
                rows,
                const SizedBox(height: 72),
                ...createRows(
                  items: [
                    TextButton.icon(
                      icon: _isBlurredSeedPhrase
                          ? ArDriveIcons.eyeClosed(
                              size: 24,
                              color: ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeFgMuted)
                          : ArDriveIcons.eyeOpen(
                              size: 24,
                              color: ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeFgMuted),
                      label: SizedBox(
                          width: 92,
                          child: Text(
                            // TODO: create/update localization keys
                            _isBlurredSeedPhrase ? 'Show Words' : 'Hide Words',
                            style: ArDriveTypography.body.smallBold(
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .colors
                                    .themeFgMuted),
                          )),
                      onPressed: () {
                        setState(() {
                          _isBlurredSeedPhrase = !_isBlurredSeedPhrase;
                        });
                      },
                    ),
                    LoginCopyButton(text: widget.mnemonic),
                  ],
                  rowCount: rowCount == 3 ? 2 : 1,
                  hGap: 16,
                  vGap: 16,
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: IntrinsicHeight(
          child: Row(children: [
        _backButton(),
        // TODO: create/update localization key
        _nextButton(text: 'I wrote it down', isDisabled: false)
      ])),
    );
  }

  Widget _buildConfirmYourSeedPhrase() {
    final screenSize = MediaQuery.of(context).size;

    final rowCount = screenSize.width > (176 * 4 + 24 * 5) ? 4 : 2;
    final width = rowCount == 4 ? 176.0 : (screenSize.width - 24 * 3) / 2;

    final topBottomPadding = rowCount == 2 ? 40.0 : 0.0;

    var wordsToCheck = createRows(
        items: _wordsToCheck.map((e) => _buildWordToCheck(width, e)).toList(),
        rowCount: rowCount,
        hGap: 24,
        vGap: 24);

    var wordOptions = createRows(
        items: _wordOptions.map((e) {
          return _buildConfirmSeedPhraseWordOption(width, e);
        }).toList(),
        rowCount: rowCount,
        hGap: 24,
        vGap: 24);

    return Scaffold(
      body: Center(
          child: SingleChildScrollView(
              padding: EdgeInsets.only(
                  top: topBottomPadding, bottom: topBottomPadding),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    // TODO: create/update localization key
                    'Confirm Your Seed Phrase',
                    textAlign: TextAlign.center,
                    style: ArDriveTypography.headline
                        .headline4Regular(
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeFgDefault)
                        .copyWith(fontSize: 32),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    // TODO: create/update localization key
                    'Please select each phrase in order to make sure it’s correct.',
                    textAlign: TextAlign.center,
                    style: ArDriveTypography.body.smallBold(
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgSubtle),
                  ),
                  const SizedBox(height: 72),
                  ...wordsToCheck,
                  const SizedBox(height: 72),
                  ...wordOptions,
                ],
              ))),
      bottomNavigationBar: IntrinsicHeight(
          child: Row(children: [
        _backButton(),

        // TODO: create/update localization key
        _nextButton(text: 'Continue', isDisabled: !_wordsAreCorrect)
      ])),
    );
  }

  Widget _buildGettingStarted() {
    PlausibleEventTracker.trackPageview(
        page: PlausiblePageView.gettingStartedPage);

    // TODO: create/update localization keys
    var cardInfos = [
      [
        'Keyfile',
        'A keyfile is another way to access your wallet. It contains encrypted information that helps us authenticate your identity. Keep it secure alongside your seed phrase.'
      ],
      [
        'Seed Phrase',
        "A seed phrase is a unique set of words that acts as the master key to your wallet. It's important because it allows us to generate your wallet from the phrase whenever you log in, which may take a moment to complete."
      ],
      [
        'Security',
        "It's crucial to safeguard both your seed phrase and keyfile. We don't retain a copy of your wallet, so losing or forgetting them may result in permanent loss of access to your funds."
      ],
      [
        'Extra Security',
        'For enhanced protection, consider storing your seed phrase in a password manager or a secure offline location. This will help prevent unauthorized access to your wallet.'
      ],
    ];

    final screenSize = MediaQuery.of(context).size;

    final rowCount = screenSize.width > (374 * 2 + 24 * 3) ? 2 : 1;
    final topBottomPadding = rowCount == 1 ? 40.0 : 16.0;

    final isDarkMode = ArDriveTheme.of(context).themeData.name == 'dark';

    return Scaffold(
      body: Stack(children: [
        Positioned(
          bottom: 0,
          right: 0,
          child: SvgPicture.asset(
            isDarkMode
                ? Resources.images.login.latticeLarge
                : Resources.images.login.latticeLargeLight,
            // fit: BoxFit.fitHeight,
          ),
        ),
        Center(
            child: SingleChildScrollView(
                padding: EdgeInsets.only(
                    top: topBottomPadding, bottom: topBottomPadding),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      // TODO: create/update localization key
                      'Getting Started',
                      textAlign: TextAlign.center,
                      style: ArDriveTypography.headline
                          .headline4Regular(
                              color: ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeFgDefault)
                          .copyWith(fontSize: 32),
                    ),
                    const SizedBox(height: 8),
                    Container(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Text(
                          // TODO: create/update localization key
                          'Learn some important information about your wallet while we begin generating it.',
                          textAlign: TextAlign.center,
                          style: ArDriveTypography.body.smallBold(
                              color: ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeFgSubtle),
                        )),
                    const SizedBox(height: 32),
                    ...createRows(
                        items: cardInfos.map(_buildCard).toList(),
                        rowCount: rowCount,
                        hGap: 24,
                        vGap: 40)
                  ],
                )))
      ]),
      bottomNavigationBar: IntrinsicHeight(
          child: Row(children: [
        _backButton(),
        // TODO: create/update localization key
        _nextButton(text: 'Continue', isDisabled: false)
      ])),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
        color: ArDriveTheme.of(context).themeData.colors.themeBgCanvas,
        child: _buildContent(context));
  }
}
