import 'dart:async';

import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

import 'accent_painter.dart';
import 'login_card.dart';
import 'max_device_sizes_constrained_box.dart';

class GenerateWalletView extends StatefulWidget {
  const GenerateWalletView({super.key});

  @override
  State<GenerateWalletView> createState() => _GenerateWalletViewState();
}

class _GenerateWalletViewState extends State<GenerateWalletView> {
  late Timer _periodicTimer;
  int _index = 0;

  // TODO: create/update localization keys
  final _messages = [
    'ArDrive helps you upload your data to the permaweb and keep it safe for generations to come!',
    'With Turbo you can pay with a credit card and increase the reliability of your uploads!',
    'You can download a copy of your keyfile from the Profile menu.',
    'If you have large drives, you can take a Snapshot to speed up the syncing time.'
  ];
  late String _message;

  @override
  void initState() {
    super.initState();

    PlausibleEventTracker.trackPageview(
        page: PlausiblePageView.walletGenerationPage);

    // TODO: create/update localization key
    _message = 'Did you know?\n\n${_messages[0]}';

    _periodicTimer = Timer.periodic(const Duration(seconds: 7), (Timer t) {
      setState(() {
        _index = (_index + 1) % _messages.length;
        // TODO: create/update localization key
        _message = 'Did you know?\n\n${_messages[_index]}';
      });
    });
  }

  @override
  void dispose() {
    _periodicTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var colors = ArDriveTheme.of(context).themeData.colors;

    return MaxDeviceSizesConstrainedBox(
      defaultMaxHeight: 798,
      maxHeightPercent: 1,
      child: SingleChildScrollView(
        child: LoginCard(
          showLattice: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                // TODO: create/update localization key
                'Generating Wallet...',
                textAlign: TextAlign.center,
                style: ArDriveTypography.headline
                    .headline4Regular(color: colors.themeFgDefault)
                    .copyWith(fontSize: 32),
              ),
              const SizedBox(height: 74),
              // Did you Know box
              Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.only(right: 16),
                    width: 227,
                    height: 150,
                    child: Text(
                      _message,
                      textAlign: TextAlign.right,
                      style: ArDriveTypography.body
                          .smallBold700(color: colors.themeFgMuted),
                    ),
                  ),
                  Container(
                      margin: const EdgeInsets.fromLTRB(239, 5, 0, 0),
                      width: 5,
                      height: 20,
                      child: CustomPaint(
                        painter: AccentPainter(lineHeight: 173),
                      )),
                ],
              ),
              const SizedBox(height: 79),
              // Info Box
              Container(
                  decoration: BoxDecoration(
                      border: Border.all(
                          color: colors.themeBorderDefault, width: 1),
                      color: colors.themeBgSurface,
                      borderRadius: BorderRadius.circular(6)),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      ArDriveIcons.info(size: 24, color: colors.themeFgSubtle),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                            // TODO: create/update localization key
                            'Nobody (including the ArDrive core team) can help you recover your wallet if the keyfile is lost. So, remember to keep it safe!',
                            style: ArDriveTypography.body
                                .buttonNormalBold(color: colors.themeFgSubtle)),
                      ),
                    ],
                  ))
            ],
          ),
        ),
      ),
    );
  }
}
