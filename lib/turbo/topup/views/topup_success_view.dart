import 'dart:math';

import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';

class TurboSuccessView extends StatelessWidget {
  const TurboSuccessView({super.key});

  @override
  Widget build(BuildContext context) {
    return SuccessView(
      successMessage: appLocalizationsOf(context).paymentSuccessful,
      detailMessage:
          appLocalizationsOf(context).yourCreditsWillBeAddedToYourAccount,
      closeButtonLabel: appLocalizationsOf(context).close,
    );
  }
}

class SuccessView extends StatefulWidget {
  final String successMessage;
  final String detailMessage;
  final String closeButtonLabel;
  final bool showConfetti;

  const SuccessView({
    super.key,
    required this.successMessage,
    required this.detailMessage,
    required this.closeButtonLabel,
    this.showConfetti = false,
  });

  @override
  State<SuccessView> createState() => _SuccessViewState();
}

class _SuccessViewState extends State<SuccessView> {
  final ConfettiController? confettiController1 = ConfettiController(
    duration: const Duration(seconds: 5),
  );

  final ConfettiController? confettiController2 = ConfettiController(
    duration: const Duration(seconds: 5),
  );

  @override
  void initState() {
    super.initState();
    if (widget.showConfetti) {
      confettiController1!.play();
      confettiController2!.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ArDriveCard(
      height: 513,
      contentPadding: EdgeInsets.zero,
      content: Column(
        children: [
          if (widget.showConfetti)
            Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ConfettiWidget(
                  numberOfParticles: 10,
                  blastDirection: -pi / 2,
                  blastDirectionality: BlastDirectionality.explosive,
                  confettiController: confettiController1!,
                  maxBlastForce: 40,
                  child: const SizedBox(
                    height: 0,
                    width: 0,
                  ),
                ),
                ConfettiWidget(
                  numberOfParticles: 10,
                  blastDirection: pi / 2,
                  blastDirectionality: BlastDirectionality.explosive,
                  confettiController: confettiController2!,
                  maxBlastForce: 40,
                  child: const SizedBox(
                    height: 0,
                    width: 0,
                  ),
                ),
              ],
            ),
          Flexible(
            flex: 1,
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 26, right: 26),
                child: ArDriveClickArea(
                  child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: ArDriveIcons.x()),
                ),
              ),
            ),
          ),
          Flexible(
            flex: 1,
            child: Column(
              children: [
                ArDriveIcons.checkCirle(
                  size: 40,
                  color: ArDriveTheme.of(context)
                      .themeData
                      .colors
                      .themeSuccessDefault,
                ),
                Text(widget.successMessage,
                    style: ArDriveTypography.body.leadBold()),
                const SizedBox(height: 16),
                Text(
                  widget.detailMessage,
                  style: ArDriveTypography.body
                      .buttonNormalRegular(
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgDefault,
                      )
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          Flexible(
            flex: 1,
            child: Align(
              alignment: Alignment.center,
              child: ArDriveButton(
                maxHeight: 44,
                maxWidth: 143,
                text: widget.closeButtonLabel,
                fontStyle: ArDriveTypography.body.buttonLargeBold(
                  color: Colors.white,
                ),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
