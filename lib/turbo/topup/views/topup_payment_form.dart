import 'dart:async';

import 'package:ardrive/components/keyboard_handler.dart';
import 'package:ardrive/dev_tools/app_dev_tools.dart';
import 'package:ardrive/dev_tools/shortcut_handler.dart';
import 'package:ardrive/turbo/topup/blocs/payment_form/payment_form_bloc.dart';
import 'package:ardrive/turbo/topup/blocs/topup_estimation_bloc.dart';
import 'package:ardrive/turbo/topup/blocs/turbo_topup_flow_bloc.dart';
import 'package:ardrive/turbo/topup/components/turbo_topup_scaffold.dart';
import 'package:ardrive/turbo/topup/views/turbo_error_view.dart';
import 'package:ardrive/turbo/utils/utils.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive/utils/split_localizations.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:responsive_builder/responsive_builder.dart';

class TurboPaymentFormView extends StatefulWidget {
  const TurboPaymentFormView({super.key});

  @override
  State<TurboPaymentFormView> createState() => TurboPaymentFormViewState();
}

class TurboPaymentFormViewState extends State<TurboPaymentFormView> {
  CardFieldInputDetails? card;
  CountryItem? _selectedCountry;
  bool _promoCodeInvalid = false;
  bool _errorFetchingPromoCode = false;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _promoCodeController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final theme = ArDriveTheme.of(context).themeData;

    final textTheme = theme.copyWith(
      textFieldTheme: theme.textFieldTheme.copyWith(
        inputTextStyle: theme.textFieldTheme.inputTextStyle.copyWith(
          fontWeight: FontWeight.w600,
          height: 1.5,
          fontSize: 16,
        ),
        requiredLabelColor: theme.colors.themeFgDefault,
        labelColor: theme.colors.themeFgDefault,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: 10,
        ),
      ),
    );

    return ArDriveTheme(
      key: const ValueKey('turbo_payment_form'),
      themeData: textTheme,
      child: ScreenTypeLayout.builder(
        mobile: (context) => _mobileView(context, textTheme.textFieldTheme),
        desktop: (context) => _desktopView(context, textTheme.textFieldTheme),
      ),
    );
  }

  Widget _mobileView(BuildContext context, ArDriveTextFieldTheme theme) {
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
                    child: ArDriveIcons.x(),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(
                left: 40,
                right: 40,
              ),
              child: Column(
                children: [
                  _header(context),
                  const Divider(height: 24),
                  _credits(context),
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: QuoteRefreshWidget(),
                  ),
                  const SizedBox(height: 16),
                  _formDesktop(
                    context,
                    theme,
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

  Widget _desktopView(BuildContext context, ArDriveTextFieldTheme theme) {
    return BlocListener<PaymentFormBloc, PaymentFormState>(
      listener: (context, state) {
        if (state is PaymentFormError) {
          showAnimatedDialog(
            context,
            barrierDismissible: false,
            content: ArDriveStandardModal(
              width: 600,
              content: TurboErrorView(
                errorType: TurboErrorType.network,
                onTryAgain: () {
                  context
                      .read<PaymentFormBloc>()
                      .add(PaymentFormLoadSupportedCountries());
                  Navigator.pop(context);
                },
                onDismiss: () {
                  Navigator.pop(context);
                },
              ),
            ),
          );
        }
      },
      child: BlocBuilder<PaymentFormBloc, PaymentFormState>(
        builder: (context, state) {
          if (state is PaymentFormLoading) {
            return TurboTopupScaffold(
              child: Container(
                height: 600,
                color: ArDriveTheme.of(context).themeData.colors.themeBgCanvas,
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            );
          }

          return ArDriveDevToolsShortcuts(
            customShortcuts: [
              Shortcut(
                modifier: LogicalKeyboardKey.shiftLeft,
                key: LogicalKeyboardKey.keyT,
                action: () {
                  ArDriveDevTools.instance
                      .showDevTools(optionalContext: context);
                },
              ),
            ],
            child: Container(
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
                            child: ArDriveIcons.x(),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 40,
                        right: 40,
                      ),
                      child: Column(
                        children: [
                          _header(context),
                          const Divider(height: 24),
                          Row(
                            children: [
                              Flexible(child: _credits(context)),
                              const Flexible(
                                flex: 1,
                                child: Padding(
                                  padding: EdgeInsets.only(left: 8.0),
                                  child: QuoteRefreshWidget(),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _formDesktop(
                            context,
                            theme,
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
            ),
          );
        },
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
                BlocBuilder<PaymentFormBloc, PaymentFormState>(
                  builder: (context, state) {
                    return Text(
                      '${convertCreditsToLiteralString(state.priceEstimate.estimate.winstonCredits)} Credits',
                      style: ArDriveTypography.body.leadBold(),
                    );
                  },
                ),
                BlocBuilder<PaymentFormBloc, PaymentFormState>(
                  builder: (context, state) {
                    final actualPaymentAmount = state
                            .priceEstimate.estimate.adjustments.isNotEmpty
                        ? state.priceEstimate.estimate.actualPaymentAmount! /
                            100
                        : state.priceEstimate.priceInCurrency;
                    return RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text:
                                '\$${(actualPaymentAmount).toStringAsFixed(2)}',
                            style: ArDriveTypography.body.captionBold(
                              color: ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeFgMuted,
                            ),
                          ),
                          if (state.priceEstimate.estimate
                                  .humanReadableDiscountPercentage !=
                              null)
                            TextSpan(
                              text:
                                  ' (${state.priceEstimate.estimate.humanReadableDiscountPercentage}% discount applied)', // TODO: localize
                              style: ArDriveTypography.body.buttonNormalRegular(
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .colors
                                    .themeFgDisabled,
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
            appLocalizationsOf(context).paymentDetails,
            style: ArDriveTypography.body
                .leadBold()
                .copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(
            height: 12,
          ),
          Text(
            appLocalizationsOf(context).thisIsAOneTimePaymentPoweredByStripe,
            style: ArDriveTypography.body.captionBold(
              color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    return ScreenTypeLayout.builder(
      mobile: (context) => Container(
        width: double.maxFinite,
        padding: const EdgeInsets.fromLTRB(40, 0, 40, 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ArDriveButton(
              maxWidth: double.maxFinite,
              maxHeight: 44,
              text: appLocalizationsOf(context).review,
              fontStyle: ArDriveTypography.body.buttonLargeBold(
                color: Colors.white,
              ),
              isDisabled: _selectedCountry == null ||
                  _nameController.text.isEmpty ||
                  !(card?.complete ?? false),
              onPressed: () {
                context
                    .read<TurboTopupFlowBloc>()
                    .add(TurboTopUpShowPaymentReviewView(
                      name: _nameController.text,
                      country: _selectedCountry!.label,
                    ));
              },
            ),
            const SizedBox(
              height: 24,
            ),
            ArDriveClickArea(
              child: GestureDetector(
                onTap: () {
                  context
                      .read<TurboTopupFlowBloc>()
                      .add(const TurboTopUpShowEstimationView());
                  // Here you have to reset the promo code
                },
                child: Text(
                  appLocalizationsOf(context).back,
                  style: ArDriveTypography.body.buttonLargeBold(
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeFgDefault,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      desktop: (context) => Container(
        width: double.maxFinite,
        padding: const EdgeInsets.fromLTRB(40, 0, 40, 36),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ArDriveClickArea(
              child: GestureDetector(
                onTap: () {
                  context
                      .read<TurboTopupFlowBloc>()
                      .add(const TurboTopUpShowEstimationView());
                },
                child: Text(
                  appLocalizationsOf(context).back,
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
              text: appLocalizationsOf(context).review,
              fontStyle: ArDriveTypography.body.buttonLargeBold(
                color: Colors.white,
              ),
              isDisabled: _selectedCountry == null ||
                  _nameController.text.isEmpty ||
                  !(card?.complete ?? false),
              onPressed: () {
                context.read<TurboTopupFlowBloc>().add(
                      TurboTopUpShowPaymentReviewView(
                        name: _nameController.text,
                        country: _selectedCountry!.label,
                      ),
                    );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _formDesktop(BuildContext context, ArDriveTextFieldTheme theme) {
    final isDarkMode = ArDriveTheme.of(context).themeData.name == 'dark';

    return SizedBox(
      width: double.maxFinite,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              nameOnCardTextField(),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              countryTextField(theme),
            ],
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(bottom: 4, right: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextFieldLabel(
                text: '${appLocalizationsOf(context).creditCard} *',
                style: ArDriveTypography.body.buttonNormalBold(
                  color: theme.requiredLabelColor,
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: isDarkMode
                  ? ArDriveTheme.of(context).themeData.colors.themeFgDefault
                  : null,
            ),
            child: CardField(
              style: ArDriveTheme.of(context)
                  .themeData
                  .textFieldTheme
                  .inputTextStyle
                  .copyWith(fontSize: 14),
              decoration: InputDecoration(
                enabledBorder: _getEnabledBorder(
                  ArDriveTheme.of(context).themeData.textFieldTheme,
                ),
                focusedBorder: _getFocusedBoder(
                  ArDriveTheme.of(context).themeData.textFieldTheme,
                ),
                errorBorder: _getErrorBorder(
                  ArDriveTheme.of(context).themeData.textFieldTheme,
                ),
                disabledBorder: _getDisabledBorder(
                  ArDriveTheme.of(context).themeData.textFieldTheme,
                ),
                focusColor: ArDriveTheme.of(context)
                    .themeData
                    .textFieldTheme
                    .inputPlaceholderColor,
                fillColor: ArDriveTheme.of(context)
                    .themeData
                    .textFieldTheme
                    .inputPlaceholderColor,
                contentPadding: const EdgeInsets.fromLTRB(13, 0, 13, 0),
              ),
              onCardChanged: (c) {
                setState(() {
                  card = c;
                });
              },
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [promoCodeLabel()]),
          Row(children: [
            promoCodeWidget(theme),
            const Flexible(child: SizedBox()),
          ]),
          const SizedBox(
            height: 16,
          ),
        ],
      ),
    );
  }

  /// TextFields
  ///
  Widget nameOnCardTextField() {
    return Expanded(
      child: ArDriveTextField(
        controller: _nameController,
        label: appLocalizationsOf(context).nameOnCard,
        isFieldRequired: true,
        useErrorMessageOffset: true,
        validator: (s) {
          String valid = s?.replaceAll(RegExp(r'[^a-zA-Z\s]'), '') ?? '';
          _nameController.text = valid;
          _nameController.selection =
              TextSelection.collapsed(offset: valid.length);

          setState(() {});

          if (valid.isEmpty) {
            return appLocalizationsOf(context).validationRequired;
          }

          return null;
        },
      ),
    );
  }

  Widget countryTextField(ArDriveTextFieldTheme theme) {
    return BlocBuilder<PaymentFormBloc, PaymentFormState>(
      builder: (context, state) {
        if (state is PaymentFormLoaded) {
          return Expanded(
            child: CountryInputDropdown(
              onClick: () {
                logger.d('CountryInputDropdown onClick');
                FocusScope.of(context).unfocus();
              },
              context: context,
              theme: theme,
              onChanged: (country) {
                setState(() {
                  _selectedCountry = country;
                });
              },
              items: state.supportedCountries.map((country) {
                return CountryItem(
                  country,
                );
              }).toList(),
              buildSelectedItem: (item) {
                return Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: item != null
                          ? theme.successBorderColor
                          : theme.defaultBorderColor,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(4),
                    color: ArDriveTheme.of(context)
                        .themeData
                        .textFieldTheme
                        .inputBackgroundColor,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          item?.label ?? '',
                          style: theme.inputTextStyle,
                        ),
                      ),
                      ArDriveIcons.carretDown(
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgDefault,
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        }

        return const SizedBox();
      },
    );
  }

  Widget promoCodeLabel() {
    return Text(
      'Promo Code', // TODO: localize
      style: ArDriveTypography.body.buttonNormalBold(
        color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
      ),
    );
  }

  Widget promoCodeWidget(ArDriveTextFieldTheme theme) {
    // HEY MATI
    return BlocBuilder<PaymentFormBloc, PaymentFormState>(
        builder: (context, state) {
      final hasPromoCodeApplied =
          state.priceEstimate.estimate.adjustments.isNotEmpty;

      logger.d('hasPromoCodeApplied: $hasPromoCodeApplied');

      return Expanded(
        child: hasPromoCodeApplied
            ? promoCodeAppliedWidget(theme)
            : promoCodeTextField(),
      );
    });
  }

  Widget promoCodeAppliedWidget(ArDriveTextFieldTheme theme) {
    final estimationBloc = context.read<TurboTopUpEstimationBloc>();
    final paymentFormBloc = context.read<PaymentFormBloc>();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: SizedBox(
            height: 48,
            child: Align(
              child: Text(
                'Promo code successfully applied', // TODO: localize
                style: ArDriveTypography.body.buttonNormalBold(
                  color: ArDriveTheme.of(context)
                      .themeData
                      .colors
                      .themeSuccessDefault,
                ),
              ),
            ),
          ),
        ),
        GestureDetector(
          onTap: () {
            setState(() {
              _promoCodeController.clear();
              estimationBloc.add(const PromoCodeChanged(null));
              paymentFormBloc.add(const PaymentFormUpdatePromoCode(null));
            });
          },
          child: Tooltip(
            message: 'Remove promo code', // TODO: localize
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: ArDriveIcons.closeCircle(
                color: ArDriveTheme.of(context)
                    .themeData
                    .colors
                    .themeSuccessDefault,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget promoCodeTextField() {
    return BlocConsumer<PaymentFormBloc, PaymentFormState>(
      listenWhen: (previous, current) => current is PaymentFormLoaded,
      listener: (context, state) {
        logger.d('PaymentFormBloc state: $state');
        if (state is PaymentFormLoaded) {
          setState(() {
            _promoCodeInvalid = state.isPromoCodeInvalid;
            _errorFetchingPromoCode = state.errorFetchingPromoCode;
          });
        }
      },
      builder: (context, state) {
        final promoCodeFetching =
            state is PaymentFormLoaded ? state.isFetchingPromoCode : false;

        return ArDriveTextField(
          controller: _promoCodeController,
          isFieldRequired: false,
          useErrorMessageOffset: true,
          isEnabled: !promoCodeFetching,
          onChanged: (_) {
            setState(() {
              _promoCodeInvalid = false;
              _errorFetchingPromoCode = false;
            });
          },
          errorMessage: _getPromoCodeErrorMessage(),
          showErrorMessage: _promoCodeInvalid || _errorFetchingPromoCode,
          suffixIcon: _applyPromoCodeButton(promoCodeFetching),
          inputFormatters: [
            TextInputFormatter.withFunction((oldValue, newValue) {
              return newValue.copyWith(
                text: newValue.text.toUpperCase().replaceAll(' ', ''),
                selection: newValue.selection,
              );
            }),
          ],
        );
      },
    );
  }

  String? _getPromoCodeErrorMessage() {
    if (_errorFetchingPromoCode) {
      return 'Error fetching the promo code'; // TODO: localize
    }
    if (_promoCodeInvalid) {
      return 'Promo code is invalid or expired'; // TODO: localize
    }

    return null;
  }

  Widget _applyPromoCodeButton(bool promoCodeFetching) {
    if (promoCodeFetching) {
      return const SizedBox(
        height: 18,
        width: 18,
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
          ),
        ),
      );
    }

    final isPromoCodeEmpty = _isPromoCodeTextFieldEmpty();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => _applyPromoCode(),
        child: MouseRegion(
          cursor: isPromoCodeEmpty
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: Text(
            'Apply', // TODO: localize
            style: ArDriveTypography.body.buttonNormalBold(
              color: ArDriveTheme.of(context).themeData.colors.themeInputText,
            ),
          ),
        ),
      ),
    );
  }

  bool _isPromoCodeTextFieldEmpty() {
    return _promoCodeController.text.isEmpty;
  }

  void _applyPromoCode() async {
    logger.d('Apply promo code clicked');

    if (_isPromoCodeTextFieldEmpty()) {
      logger.d('Promo code is empty');
      return;
    }

    final paymentFormBloc = context.read<PaymentFormBloc>();
    final estimationBloc = context.read<TurboTopUpEstimationBloc>();

    // Here you set the promo code to the bloc
    paymentFormBloc.add(PaymentFormUpdatePromoCode(_promoCodeController.text));
    estimationBloc.add(PromoCodeChanged(_promoCodeController.text));
  }

  InputBorder _getBorder(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: BorderSide(color: color, width: 2),
    );
  }

  InputBorder _getEnabledBorder(
    ArDriveTextFieldTheme theme,
  ) {
    if (card?.complete ?? false) {
      return _getSuccessBorder(theme);
    }

    return _getBorder(theme.defaultBorderColor);
  }

  InputBorder _getFocusedBoder(ArDriveTextFieldTheme theme) {
    return _getBorder(
      ArDriveTheme.of(context).themeData.colors.themeFgDefault,
    );
  }

  InputBorder _getDisabledBorder(ArDriveTextFieldTheme theme) {
    return _getBorder(theme.inputDisabledBorderColor);
  }

  InputBorder _getErrorBorder(ArDriveTextFieldTheme theme) {
    return _getBorder(theme.errorBorderColor);
  }

  InputBorder _getSuccessBorder(ArDriveTextFieldTheme theme) {
    return _getBorder(theme.successBorderColor);
  }
}

class TimerWidget extends StatefulWidget {
  final int durationInSeconds;
  final VoidCallback onFinished;
  final TextStyle? textStyle;
  final bool isFetching;
  final bool hasError;
  final bool humanReadable;
  final bool humanReadableWithPadding;
  final bool boldTimer;

  const TimerWidget({
    super.key,
    required this.durationInSeconds,
    required this.onFinished,
    this.textStyle,
    this.isFetching = false,
    this.hasError = false,
    required this.humanReadable,
    this.humanReadableWithPadding = false,
    this.boldTimer = false,
  });

  @override
  TimerWidgetState createState() => TimerWidgetState();
}

class TimerWidgetState extends State<TimerWidget> {
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
          widget.onFinished(); // Call the provided callback function
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
    Color textColor;
    if (_secondsLeft < 30) {
      textColor = ArDriveTheme.of(context).themeData.colors.themeErrorDefault;
    } else if (_secondsLeft < 60) {
      textColor = ArDriveTheme.of(context).themeData.colors.themeWarningMuted;
    } else {
      textColor = ArDriveTheme.of(context).themeData.colors.themeFgDefault;
    }

    if (widget.isFetching) {
      return Text(
        appLocalizationsOf(context).fetchingNewQuote,
        style: ArDriveTypography.body.buttonNormalBold().copyWith(
              color: textColor,
              fontWeight: FontWeight.w700,
            ),
      );
    } else if (widget.hasError) {
      return Text(
        appLocalizationsOf(context).errorFetchingQuote,
        style: ArDriveTypography.body
            .buttonNormalBold(
              color:
                  ArDriveTheme.of(context).themeData.colors.themeErrorDefault,
            )
            .copyWith(
              fontWeight: FontWeight.w700,
            ),
      );
    }

    final formattedDuration = _formatDuration(_secondsLeft);

    if (!widget.humanReadable) {
      final originalText =
          appLocalizationsOf(context).quoteUpdatesIn(formattedDuration);
      final widgetParts = splitTranslationsWithMultipleStyles<Widget>(
          originalText: originalText,
          defaultMapper: (textPart) => RichText(
                text: TextSpan(
                  text: textPart,
                  style: ArDriveTypography.body.buttonNormalBold().copyWith(
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgDefault,
                      ),
                ),
              ),
          parts: {
            formattedDuration: (text) {
              final richText = RichText(
                text: TextSpan(
                  text: text,
                  style: ArDriveTypography.body.buttonNormalBold().copyWith(
                        color: textColor,
                        fontWeight: widget.boldTimer ? FontWeight.w700 : null,
                      ),
                ),
              );

              if (widget.humanReadableWithPadding) {
                return Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: richText,
                );
              } else {
                return richText;
              }
            }
          });

      return Column(
        children: widgetParts,
      );
    } else {
      return Text(
        formattedDuration,
        style: widget.textStyle?.copyWith(color: textColor),
      );
    }
  }
}

abstract class InputDropdownItem {
  const InputDropdownItem(this.label);

  final String label;
}

class InputDropdownMenu<T extends InputDropdownItem> extends StatefulWidget {
  const InputDropdownMenu({
    super.key,
    required this.items,
    this.onClick,
    this.selectedItem,
    required this.buildSelectedItem,
    this.label,
    this.backgroundColor,
    this.onChanged,
    this.anchor = const Aligned(
      follower: Alignment.topLeft,
      target: Alignment.bottomLeft,
      offset: Offset(0, 4),
    ),
    this.itemsTextStyle,
  });

  final List<T> items;
  final T? selectedItem;
  final Widget Function(T?) buildSelectedItem;
  final String? label;
  final Function(T)? onChanged;
  final Function()? onClick;
  final Anchor anchor;
  final TextStyle? itemsTextStyle;
  final Color? backgroundColor;

  @override
  State<InputDropdownMenu> createState() => _InputDropdownMenuState<T>();
}

class _InputDropdownMenuState<T extends InputDropdownItem>
    extends State<InputDropdownMenu<T>> {
  T? _selectedItem;

  @override
  initState() {
    super.initState();
    _selectedItem = widget.selectedItem;
  }

  @override
  Widget build(BuildContext context) {
    return ArDriveClickArea(
      child: ArDriveDropdown(
        showScrollbars: true,
        onClick: widget.onClick,
        maxHeight: 275,
        width: 200,
        anchor: widget.anchor,
        items: widget.items
            .map(
              (e) => ArDriveDropdownItem(
                content: Container(
                  width: 200,
                  alignment: Alignment.center,
                  height: 44,
                  color: widget.backgroundColor ??
                      ArDriveTheme.of(context)
                          .themeData
                          .textFieldTheme
                          .inputBackgroundColor,
                  child: Text(
                    e.label,
                    style: widget.itemsTextStyle ??
                        ArDriveTypography.body.captionBold(
                          color: ArDriveTheme.of(context)
                              .themeData
                              .textFieldTheme
                              .inputTextStyle
                              .color,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ),
                onClick: () {
                  setState(() {
                    _selectedItem = e;
                  });

                  if (widget.onChanged != null) {
                    widget.onChanged!(e);
                  }
                },
              ),
            )
            .toList(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.label != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4, right: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextFieldLabel(
                    text: widget.label!,
                    style: ArDriveTypography.body.buttonNormalBold(
                      color: ArDriveTheme.of(context)
                          .themeData
                          .textFieldTheme
                          .requiredLabelColor,
                    ),
                  ),
                ),
              ),
            widget.buildSelectedItem(_selectedItem),
          ],
        ),
      ),
    );
  }
}

class CountryItem implements InputDropdownItem {
  @override
  final String label;

  const CountryItem(this.label);
}

class CountryInputDropdown extends InputDropdownMenu<CountryItem> {
  CountryInputDropdown({
    Key? key,
    required List<CountryItem> items,
    required Widget Function(CountryItem?) buildSelectedItem,
    required ArDriveTextFieldTheme theme,
    CountryItem? selectedItem,
    required Function(CountryItem) onChanged,
    Function()? onClick,
    required BuildContext context,
  }) : super(
          key: key,
          items: items,
          onClick: onClick,
          selectedItem: selectedItem,
          buildSelectedItem: buildSelectedItem,
          label: '${appLocalizationsOf(context).country} *',
          onChanged: onChanged,
          itemsTextStyle: theme.inputTextStyle,
          backgroundColor: theme.inputBackgroundColor,
        );
}

class QuoteRefreshWidget extends StatefulWidget {
  const QuoteRefreshWidget({super.key});

  @override
  QuoteRefreshWidgetState createState() => QuoteRefreshWidgetState();
}

class QuoteRefreshWidgetState extends State<QuoteRefreshWidget> {
  @override
  Widget build(BuildContext context) {
    return ScreenTypeLayout.builder(
      mobile: (context) => ArDriveCard(
        contentPadding: const EdgeInsets.symmetric(
          vertical: 13,
        ),
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            BlocBuilder<PaymentFormBloc, PaymentFormState>(
              builder: (context, state) {
                if (state is PaymentFormQuoteLoadFailure) {
                  return const SizedBox();
                }

                return Row(
                  children: [
                    TimerWidget(
                      humanReadable: true,
                      humanReadableWithPadding: true,
                      textStyle: ArDriveTypography.body.captionBold(
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgDefault,
                      ),
                      key: state is PaymentFormQuoteLoaded
                          ? const ValueKey('reset_timer')
                          : null,
                      durationInSeconds: state.quoteExpirationTimeInSeconds,
                      onFinished: () {
                        logger.d('fetching quote');
                        context
                            .read<PaymentFormBloc>()
                            .add(PaymentFormUpdateQuote());
                      },
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 4),
            BlocBuilder<PaymentFormBloc, PaymentFormState>(
              builder: (context, state) {
                if (state is PaymentFormLoadingQuote) {
                  return const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  );
                }

                if (state is PaymentFormQuoteLoadFailure) {
                  return ArDriveClickArea(
                    child: GestureDetector(
                      onTap: () {
                        context
                            .read<PaymentFormBloc>()
                            .add(PaymentFormUpdateQuote());
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                appLocalizationsOf(context).unableToUpdateQuote,
                                style: ArDriveTypography.body.captionBold(
                                  color: ArDriveTheme.of(context)
                                      .themeData
                                      .colors
                                      .themeErrorDefault,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            ArDriveIcons.refresh(
                              color: ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeErrorDefault,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                return ArDriveClickArea(
                  child: GestureDetector(
                    onTap: () {
                      context
                          .read<PaymentFormBloc>()
                          .add(PaymentFormUpdateQuote());
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ArDriveIcons.refresh(
                          color: ArDriveTheme.of(context)
                              .themeData
                              .colors
                              .themeFgDefault,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          appLocalizationsOf(context).refresh,
                          style: ArDriveTypography.body.captionBold(
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeFgDefault,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            )
          ],
        ),
      ),
      desktop: (context) => ArDriveCard(
        contentPadding: const EdgeInsets.symmetric(
          vertical: 13,
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            BlocBuilder<PaymentFormBloc, PaymentFormState>(
              builder: (context, state) {
                if (state is PaymentFormQuoteLoadFailure) {
                  return const SizedBox();
                }

                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TimerWidget(
                      humanReadable: true,
                      key: state is PaymentFormQuoteLoaded
                          ? const ValueKey('reset_timer')
                          : null,
                      durationInSeconds: state.quoteExpirationTimeInSeconds,
                      onFinished: () {
                        logger.d('fetching quote');
                        context
                            .read<PaymentFormBloc>()
                            .add(PaymentFormUpdateQuote());
                      },
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 4),
            Flexible(
              child: BlocBuilder<PaymentFormBloc, PaymentFormState>(
                builder: (context, state) {
                  if (state is PaymentFormLoadingQuote) {
                    return const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    );
                  }

                  if (state is PaymentFormQuoteLoadFailure) {
                    return ArDriveClickArea(
                      child: GestureDetector(
                        onTap: () {
                          context
                              .read<PaymentFormBloc>()
                              .add(PaymentFormUpdateQuote());
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  appLocalizationsOf(context)
                                      .unableToUpdateQuote,
                                  style: ArDriveTypography.body.captionBold(
                                    color: ArDriveTheme.of(context)
                                        .themeData
                                        .colors
                                        .themeErrorDefault,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              ArDriveIcons.refresh(
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .colors
                                    .themeErrorDefault,
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  return ArDriveClickArea(
                    child: GestureDetector(
                      onTap: () {
                        context
                            .read<PaymentFormBloc>()
                            .add(PaymentFormUpdateQuote());
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ArDriveIcons.refresh(
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeFgDefault,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            appLocalizationsOf(context).refresh,
                            style: ArDriveTypography.body.captionBold(
                              color: ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeFgDefault,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }
}
