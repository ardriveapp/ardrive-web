import 'package:ardrive/turbo/topup/blocs/turbo_topup_flow_bloc.dart';
import 'package:ardrive/turbo/topup/views/turbo_payment_form.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../misc/resources.dart';

class TurboReviewView extends StatefulWidget {
  const TurboReviewView({super.key});

  @override
  State<TurboReviewView> createState() => _TurboReviewViewState();
}

class _TurboReviewViewState extends State<TurboReviewView> {
  @override
  Widget build(BuildContext context) {
    final theme = ArDriveTheme.of(context).themeData;

    // custom theme for the text fields on the top-up form
    final textTheme = theme.copyWith(
      textFieldTheme: theme.textFieldTheme.copyWith(
        inputBackgroundColor: theme.colors.themeBgCanvas,
        labelColor: theme.colors.themeAccentDisabled,
        requiredLabelColor: theme.colors.themeAccentDisabled,
        inputTextStyle: theme.textFieldTheme.inputTextStyle.copyWith(
          color: theme.colors.themeFgMuted,
          fontWeight: FontWeight.w600,
          height: 1.5,
          fontSize: 16,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: 8,
        ),
        labelStyle: TextStyle(
          color: theme.colors.themeAccentDisabled,
          fontWeight: FontWeight.w600,
          height: 1.5,
          fontSize: 16,
        ),
      ),
    );

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
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
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 40.0),
              child: Text(
                'Review',
                style: ArDriveTypography.body
                    .leadBold()
                    .copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(40.0),
            child: ArDriveCard(
              contentPadding: const EdgeInsets.all(0),
              backgroundColor: ArDriveTheme.of(context).themeData.colors.shadow,
              content: Column(
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.only(top: 24, left: 24, right: 24),
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SvgPicture.asset(
                            Resources.images.brand.turbo,
                            height: 15,
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeAccentDisabled,
                            colorBlendMode: BlendMode.srcIn,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(
                          height: 18,
                        ),
                        Text(
                          '14.0944',
                          style: ArDriveTypography.headline
                              .headline4Regular(
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .colors
                                    .themeFgMuted,
                              )
                              .copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        Text(
                          'Credits',
                          style: ArDriveTypography.body.buttonLargeRegular(
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeAccentDisabled,
                          ),
                        ),
                        const SizedBox(
                          height: 40,
                        ),
                        const Divider(),
                        Row(
                          children: [
                            Text(
                              'Subtotal',
                              style: ArDriveTypography.body.buttonNormalBold(
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .colors
                                    .themeAccentDisabled,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '\$25.00',
                              style: ArDriveTypography.body.buttonNormalBold(
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .colors
                                    .themeAccentDisabled,
                              ),
                            ),
                          ],
                        ),
                        const Divider(
                          height: 32,
                        ),
                        Row(
                          children: [
                            Text(
                              'Fees',
                              style: ArDriveTypography.body.buttonNormalBold(
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .colors
                                    .themeAccentDisabled,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '\$0.50',
                              style: ArDriveTypography.body.buttonNormalBold(
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .colors
                                    .themeAccentDisabled,
                              ),
                            ),
                          ],
                        ),
                        const Divider(
                          height: 32,
                        ),
                        Row(
                          children: [
                            Text(
                              'Total taxes',
                              style: ArDriveTypography.body.buttonNormalBold(
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .colors
                                    .themeAccentDisabled,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '\$2',
                              style: ArDriveTypography.body.buttonNormalBold(
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .colors
                                    .themeAccentDisabled,
                              ),
                            ),
                          ],
                        ),
                        const Divider(
                          height: 32,
                        ),
                        Row(
                          children: [
                            Text(
                              'Total',
                              style: ArDriveTypography.body.buttonNormalBold(),
                            ),
                            const Spacer(),
                            Text(
                              '\$27.50',
                              style: ArDriveTypography.body
                                  .buttonNormalBold()
                                  .copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(
                    height: 24,
                  ),
                  Container(
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeBgSurface,
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 24,
                    ),
                    child: Row(
                      children: [
                        TimerWidget(
                          durationInSeconds: 600,
                          onFinished: () {},
                          builder: (context, seconds) {
                            Color textColor;
                            if (seconds < 590) {
                              textColor = ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeErrorDefault;
                            } else if (seconds < 595) {
                              textColor = ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeWarningMuted;
                            } else {
                              textColor = ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeAccentDisabled;
                            }

                            String formatDuration(int seconds) {
                              int minutes = seconds ~/ 60;
                              int remainingSeconds = seconds % 60;
                              String minutesStr =
                                  minutes.toString().padLeft(2, '0');
                              String secondsStr =
                                  remainingSeconds.toString().padLeft(2, '0');
                              return '$minutesStr:$secondsStr';
                            }

                            return RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'Quote updates in ',
                                    style: ArDriveTypography.body
                                        .buttonNormalBold()
                                        .copyWith(
                                          color: ArDriveTheme.of(context)
                                              .themeData
                                              .colors
                                              .themeAccentDisabled,
                                        ),
                                  ),
                                  TextSpan(
                                    text: formatDuration(seconds),
                                    style: ArDriveTypography.body
                                        .buttonNormalBold()
                                        .copyWith(
                                          color: textColor,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 40.0, right: 40, bottom: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Please leave an email if you want a receipt.',
                  style: ArDriveTypography.body.buttonNormalBold(
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeAccentDisabled,
                  ),
                ),
                const SizedBox(
                  height: 16,
                ),
                ArDriveTheme(
                  key: const ValueKey('turbo_payment_form'),
                  themeData: textTheme,
                  child: const ArDriveTextField(),
                ),
                const SizedBox(
                  height: 16,
                ),
                ArDriveCheckBox(
                  title: 'Keep me up to date on news and promotions.',
                  titleStyle: ArDriveTypography.body.buttonNormalBold(
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeAccentDisabled,
                  ),
                  checked: true,
                ),
                const Divider(
                  height: 80,
                ),
                _footer(context)
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    return SizedBox(
      width: double.maxFinite,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ArDriveClickArea(
            child: GestureDetector(
              onTap: () {
                context
                    .read<TurboTopupFlowBloc>()
                    .add(const TurboTopUpShowPaymentFormView());
              },
              child: Text(
                // TODO: localize
                'Back',
                style: ArDriveTypography.body.buttonLargeBold(
                  color: ArDriveTheme.of(context)
                      .themeData
                      .colors
                      .themeAccentDisabled,
                ),
              ),
            ),
          ),
          ArDriveButton(
            maxHeight: 44,
            maxWidth: 143,
            // TODO: localize
            text: 'Pay',
            fontStyle: ArDriveTypography.body.buttonLargeBold(
              color: Colors.white,
            ),
            onPressed: () {
              context
                  .read<TurboTopupFlowBloc>()
                  .add(const TurboTopUpShowSuccessView());
            },
          ),
        ],
      ),
    );
  }
}
