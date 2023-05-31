import 'dart:async';

import 'package:ardrive/utils/credit_card_validations.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_multi_formatter/flutter_multi_formatter.dart';
import 'package:responsive_builder/responsive_builder.dart';

class TurboPaymentFormView extends StatefulWidget {
  const TurboPaymentFormView({super.key});

  @override
  State<TurboPaymentFormView> createState() => TurboPaymentFormViewState();
}

class TurboPaymentFormViewState extends State<TurboPaymentFormView> {
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

    return ArDriveTheme(
      key: const ValueKey('turbo_payment_form'),
      themeData: textTheme,
      child: ScreenTypeLayout.builder(
        mobile: (context) => _mobileView(context),
        desktop: (context) => _desktopView(context),
      ),
    );
  }

  Widget _mobileView(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 16),
        _header(context),
        const Divider(height: 16),
        // _body(context),
        const SizedBox(height: 16),
        // _footer(context),
      ],
    );
  }

  Widget _desktopView(BuildContext context) {
    return Container(
      color: ArDriveTheme.of(context).themeData.colors.themeBgCanvas,
      child: SingleChildScrollView(
        child: Column(
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
            Padding(
              padding: const EdgeInsets.only(
                top: 14.0,
                left: 40,
                right: 40,
              ),
              child: Column(
                children: [
                  _header(context),
                  const Divider(height: 24),
                  _credits(context),
                  const SizedBox(height: 16),
                  _formDesktop(
                    context,
                  ),
                ],
              ),
            ),
            const Divider(height: 16),
            const SizedBox(height: 24),
            _footer(context),
          ],
        ),
      ),
    );
  }

  // text fields
  Widget nameOnCardTextField() {
    return Expanded(
      child: ArDriveTextField(
        label: 'Name on Card',
        isFieldRequired: true,
        useErrorMessageOffset: true,
        validator: (s) {
          if (s == null || s.isEmpty) {
            return 'Can\'t be empty';
          }
          return null;
        },
      ),
    );
  }

  Widget cardNumberTextField() {
    return Expanded(
      child: ArDriveTextField(
        label: 'Card Number',
        isFieldRequired: true,
        useErrorMessageOffset: true,
        validator: (s) {
          if (s == null || !validateCreditCardNumber(s)) {
            return 'Invalid credit card number';
          }
          return null;
        },
        inputFormatters: [
          CreditCardNumberInputFormatter(
            useSeparators: true,
            onCardSystemSelected: (cardSystem) {
              logger.d('card system selected: $cardSystem');
            },
          )
        ],
      ),
    );
  }

  Widget expiryDateTextField() {
    return Expanded(
      child: ArDriveTextField(
        label: 'Expiry Date',
        isFieldRequired: true,
        useErrorMessageOffset: true,
        validator: (s) {
          if (s == null || !validateCreditCardExpiryDate(s)) {
            return 'Invalid expiry date';
          }
          return null;
        },
        inputFormatters: [CreditCardExpirationDateFormatter()],
      ),
    );
  }

  Widget cvcTextField() {
    return Expanded(
      child: ArDriveTextField(
        label: 'CVC',
        useErrorMessageOffset: true,
        validator: (s) {
          if (s == null || !validateCreditCardCVC(s, '4242 4242 4242 4242')) {
            return 'Please enter a valid CVC';
          }
          return null;
        },
        isFieldRequired: true,
        inputFormatters: [CreditCardCvcInputFormatter()],
      ),
    );
  }

  Widget countryTextField() {
    return Expanded(
      child: ArDriveTextField(
        label: 'Country',
        hintText: 'United States',
        isFieldRequired: true,
        useErrorMessageOffset: true,
        validator: (s) {
          if (s == null || s.isEmpty) {
            return 'Can\'t be empty';
          }
          return null;
        },
      ),
    );
  }

  Widget stateTextField() {
    return Expanded(
      child: ArDriveTextField(
        label: 'State',
        useErrorMessageOffset: true,
        validator: (s) {
          if (s == null || s.isEmpty) {
            return 'Can\'t be empty';
          }
          return null;
        },
      ),
    );
  }

  Widget addressLine1TextField() {
    return Expanded(
      child: ArDriveTextField(
        label: 'Address Line 1',
        isFieldRequired: true,
        useErrorMessageOffset: true,
        validator: (s) {
          if (s == null || s.isEmpty) {
            return 'Can\'t be empty';
          }
          return null;
        },
      ),
    );
  }

  Widget addressLine2TextField() {
    return Expanded(
      child: ArDriveTextField(
        label: 'Address Line 2',
        isFieldRequired: true,
        useErrorMessageOffset: true,
        validator: (s) {
          if (s == null || s.isEmpty) {
            return 'Can\'t be empty';
          }
          return null;
        },
      ),
    );
  }

  Widget postalCodeTextField() {
    return Flexible(
      flex: 1,
      child: ArDriveTextField(
        label: 'Postal Code',
        isFieldRequired: true,
        useErrorMessageOffset: true,
        validator: (s) {
          if (s == null || s.isEmpty) {
            return 'Can\'t be empty';
          }
          return null;
        },
      ),
    );
  }

  Widget _quoteRefresh(BuildContext context) {
    return ArDriveCard(
      contentPadding: const EdgeInsets.symmetric(
        vertical: 13,
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // TODO: localize
              Text(
                'Quote updates in ',
                style: ArDriveTypography.body.captionBold(
                  color:
                      ArDriveTheme.of(context).themeData.colors.themeFgDisabled,
                ),
              ),
              TimerWidget(
                durationInSeconds: 60 * 10,
                fetchQuoteCallback: () {
                  logger.d('fetching quote');
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ArDriveIcons.refresh(
                color:
                    ArDriveTheme.of(context).themeData.colors.themeFgDisabled,
                size: 16,
              ),
              const SizedBox(width: 4),
              // TODO: localize
              Text(
                'Refresh',
                style: ArDriveTypography.body.captionBold(
                  color:
                      ArDriveTheme.of(context).themeData.colors.themeFgDisabled,
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _credits(BuildContext context) {
    return SizedBox(
      width: double.maxFinite,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // TODO: localize
                  '14.0944 Credits',
                  style: ArDriveTypography.body.leadBold(),
                ),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '\$25',
                        style: ArDriveTypography.body.captionBold(
                          color: ArDriveTheme.of(context)
                              .themeData
                              .colors
                              .themeFgMuted,
                        ),
                      ),
                      TextSpan(
                        text: ' + taxes and fees',
                        style: ArDriveTypography.body.captionBold(
                          color: ArDriveTheme.of(context)
                              .themeData
                              .colors
                              .themeAccentDisabled,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: _quoteRefresh(
                context,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return SizedBox(
      width: double.maxFinite,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            // TODO: localize
            'Payment Details',
            style: ArDriveTypography.body
                .leadBold()
                .copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(
            height: 12,
          ),
          Text(
            // TODO: localize
            'This is a one-time payment, powered by Stripe.',
            style: ArDriveTypography.body.captionRegular(
              color: ArDriveTheme.of(context).themeData.colors.themeFgDisabled,
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    return Container(
      width: double.maxFinite,
      padding: const EdgeInsets.fromLTRB(40, 0, 40, 36),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ArDriveClickArea(
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).pop();
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
            // TODO: localize
            text: 'Review',
            fontStyle: ArDriveTypography.body.buttonLargeBold(
              color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
            ),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _formDesktop(BuildContext context) {
    return SizedBox(
      width: double.maxFinite,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              nameOnCardTextField(),
              const SizedBox(width: 24),
              cardNumberTextField(),
            ],
          ),
          Row(
            children: [
              expiryDateTextField(),
              const SizedBox(width: 24),
              cvcTextField(),
            ],
          ),
          Row(
            children: [
              countryTextField(),
              const SizedBox(width: 24),
              stateTextField(),
            ],
          ),
          Row(
            children: [
              addressLine1TextField(),
              const SizedBox(width: 24),
              addressLine2TextField(),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              postalCodeTextField(),
              Flexible(flex: 1, child: Container()),
            ],
          ),
        ],
      ),
    );
  }
}

class TimerWidget extends StatefulWidget {
  final int durationInSeconds;
  final VoidCallback fetchQuoteCallback;

  const TimerWidget(
      {super.key,
      required this.durationInSeconds,
      required this.fetchQuoteCallback});

  @override
  // ignore: library_private_types_in_public_api
  _TimerWidgetState createState() => _TimerWidgetState();
}

class _TimerWidgetState extends State<TimerWidget> {
  late Timer _timer;
  int _secondsLeft = 0;

  @override
  void initState() {
    super.initState();
    startTimer();
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void startTimer() {
    _secondsLeft = widget.durationInSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_secondsLeft > 0) {
          _secondsLeft--;
        } else {
          // Timer completed, fetch the quote again or perform any desired action
          _timer.cancel();
          widget.fetchQuoteCallback(); // Call the provided callback function
        }
      });
    });
  }

  String _formatDuration(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    String minutesStr = minutes.toString().padLeft(2, '0');
    String secondsStr = remainingSeconds.toString().padLeft(2, '0');
    return '$minutesStr:$secondsStr';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _formatDuration(_secondsLeft),
      style: ArDriveTypography.body.captionBold(
        color: ArDriveTheme.of(context).themeData.colors.themeFgDisabled,
      ),
    );
  }
}
