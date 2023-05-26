import 'dart:async';

import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';

class TurboPaymentFormView extends StatefulWidget {
  const TurboPaymentFormView({super.key});

  @override
  State<TurboPaymentFormView> createState() => TurboPaymentFormViewState();
}

class TurboPaymentFormViewState extends State<TurboPaymentFormView> {
  @override
  Widget build(BuildContext context) {
    return ScreenTypeLayout.builder(
      mobile: (context) => _mobileView(context),
      desktop: (context) => _desktopView(context),
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
    return SingleChildScrollView(
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
          const SizedBox(height: 40),
          _emailSection(context),
          _footer(context),
        ],
      ),
    );
  }

  Widget _quoteRefresh(BuildContext context) {
    return SizedBox(
      width: double.maxFinite,
      child: Row(
        children: [
          // TODO: localize
          Text(
            'Quote updates in ',
            style: ArDriveTypography.body.captionBold(
              color: ArDriveTheme.of(context).themeData.colors.themeFgDisabled,
            ),
          ),
          TimerWidget(
            durationInSeconds: 30,
            fetchQuoteCallback: () {
              logger.d('fetching quote');
            },
          ),
          SizedBox(width: 18),
          // quote refresh widget
          ArDriveIcons.refresh(
            color: ArDriveTheme.of(context).themeData.colors.themeFgDisabled,
            size: 16,
          ),
          SizedBox(width: 4),
          // TODO: localize
          Text(
            'Refresh',
            style: ArDriveTypography.body.captionBold(
              color: ArDriveTheme.of(context).themeData.colors.themeFgDisabled,
            ),
          ),
        ],
      ),
    );
  }

  Widget _credits(BuildContext context) {
    return SizedBox(
      width: double.maxFinite,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            // TODO: localize
            '14.0944 Credits',
            style: ArDriveTypography.body.leadBold(),
          ),
          // quote refresh widget
          _quoteRefresh(context),
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
            'Payment',
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
      padding: const EdgeInsets.fromLTRB(40, 40, 40, 36),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ArDriveClickArea(
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).pop();
              },
              child: Row(
                children: [
                  Transform.translate(
                    offset: Offset(0, 2),
                    child: ArDriveIcons.carretLeft(
                      color: ArDriveTheme.of(context)
                          .themeData
                          .colors
                          .themeFgDisabled,
                    ),
                  ),
                  Text(
                    'Back',
                    style: ArDriveTypography.body.buttonLargeRegular(
                      color: ArDriveTheme.of(context)
                          .themeData
                          .colors
                          .themeFgDisabled,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Text(
            'Fee',
            style: ArDriveTypography.body.buttonLargeRegular(
              color: ArDriveTheme.of(context).themeData.colors.themeFgDisabled,
            ),
          ),
          ArDriveButton(
            text: 'Pay \$27.50',
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _formDesktop(BuildContext context) {
    return const SizedBox(
      width: double.maxFinite,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ArDriveTextField(
                  label: 'Name on Card',
                  hintText: 'John Doe',
                ),
              ),
              SizedBox(width: 24),
              Expanded(
                child: ArDriveTextField(
                  label: 'Card Number',
                  hintText: '4242 4242 4242 4242',
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: ArDriveTextField(
                  label: 'Expiry Date',
                  hintText: 'MM/YY',
                ),
              ),
              SizedBox(width: 24),
              Expanded(
                child: ArDriveTextField(
                  label: 'CVC',
                  hintText: '123',
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: ArDriveTextField(
                  label: 'Country',
                  hintText: 'United States',
                ),
              ),
              SizedBox(width: 24),
              Expanded(
                child: ArDriveTextField(
                  label: 'ZIP',
                  hintText: '12345',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  _emailSection(BuildContext context) {
    return Container(
      color: ArDriveTheme.of(context).themeData.colors.shadow,
      width: double.maxFinite,
      padding: const EdgeInsets.fromLTRB(40, 20, 40, 36),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Email', style: ArDriveTypography.body.captionBold()),
          Text(
            'Please leave email if you want a receipt',
            style: ArDriveTypography.body.captionRegular(
              color: ArDriveTheme.of(context).themeData.colors.themeFgDisabled,
            ),
          ),
          SizedBox(height: 4),
          ArDriveTextField(),
          SizedBox(height: 16),
          ArDriveCheckBox(
            title: 'Keep me up to date on news and promotions.',
            titleStyle: ArDriveTypography.body.captionRegular(
              color: ArDriveTheme.of(context).themeData.colors.themeFgDisabled,
            ),
          ),
          SizedBox(height: 16),
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
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
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

  String formatDuration(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    String minutesStr = minutes.toString().padLeft(2, '0');
    String secondsStr = remainingSeconds.toString().padLeft(2, '0');
    return '$minutesStr:$secondsStr';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      formatDuration(_secondsLeft),
      style: ArDriveTypography.body.captionBold(
        color: ArDriveTheme.of(context).themeData.colors.themeFgDisabled,
      ),
    );
  }
}
