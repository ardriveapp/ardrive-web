import 'dart:async';

import 'package:ardrive/components/keyboard_handler.dart';
import 'package:ardrive/dev_tools/app_dev_tools.dart';
import 'package:ardrive/dev_tools/shortcut_handler.dart';
import 'package:ardrive/turbo/topup/blocs/payment_form/payment_form_bloc.dart';
import 'package:ardrive/turbo/topup/blocs/turbo_topup_flow_bloc.dart';
import 'package:ardrive/utils/credit_card_validations.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive/utils/winston_to_ar.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_multi_formatter/flutter_multi_formatter.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:responsive_builder/responsive_builder.dart';

class TurboPaymentFormView extends StatefulWidget {
  const TurboPaymentFormView({super.key});

  @override
  State<TurboPaymentFormView> createState() => TurboPaymentFormViewState();
}

class TurboPaymentFormViewState extends State<TurboPaymentFormView> {
  late final GlobalKey<ArDriveFormState> _formKey;
  late final TextEditingController _cardNumberController;
  late final TextEditingController _expiryDateController;
  late final TextEditingController _cvvController;
  late final TextEditingController _nameController;
  late final TextEditingController _stateController;
  late final TextEditingController _addressLine1Controller;
  late final TextEditingController _addressLine2Controller;
  late final TextEditingController _postalCodeController;
  CardFieldInputDetails? card;
  CountryItem? _selectedCountry;

  @override
  initState() {
    super.initState();
    _formKey = GlobalKey<ArDriveFormState>(debugLabel: 'TurboPaymentForm');
    _cardNumberController = TextEditingController();
    _expiryDateController = TextEditingController();
    _cvvController = TextEditingController();
    _nameController = TextEditingController();
    _stateController = TextEditingController();
    _addressLine1Controller = TextEditingController();
    _addressLine2Controller = TextEditingController();
    _postalCodeController = TextEditingController();
    card = null;

    _listenToFormChanges();
  }

  bool _isFormValid = false;

  void _listenToFormChanges() {
    _cardNumberController.addListener(_onFormChange);
    _expiryDateController.addListener(_onFormChange);
    _cvvController.addListener(_onFormChange);
    _nameController.addListener(_onFormChange);
    _stateController.addListener(_onFormChange);
    _addressLine1Controller.addListener(_onFormChange);
    _addressLine2Controller.addListener(_onFormChange);
    _postalCodeController.addListener(_onFormChange);
  }

  void prePopulateWithHardcodedData() {
    _cardNumberController.text = '4242424242424242';
    _expiryDateController.text = '06/26';
    _cvvController.text = '123';
    _nameController.text = 'John Doe';
    _stateController.text = 'California';
    _addressLine1Controller.text = '123 Main St';
    _addressLine2Controller.text = 'Apt 1';
    _postalCodeController.text = '90210';

    setState(() {});
  }

  void _onFormChange() async {
    _isFormValid = _formKey.currentState?.validateSync() ?? false;

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = ArDriveTheme.of(context).themeData;

    // custom theme for the text fields on the top-up form
    final textTheme = theme.copyWith(
      textFieldTheme: theme.textFieldTheme.copyWith(
        // inputBackgroundColor: theme.colors.themeBgCanvas,
        // labelColor: theme.colors.themeAccentDisabled,
        // requiredLabelColor: theme.colors.themeAccentDisabled,
        inputTextStyle: theme.textFieldTheme.inputTextStyle.copyWith(
          // color: theme.colors.themeFgMuted,
          fontWeight: FontWeight.w600,
          height: 1.5,
          fontSize: 16,
        ),
        requiredLabelColor: theme.colors.themeAccentDisabled,
        labelColor: theme.colors.themeAccentDisabled,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: 10,
        ),
        // labelStyle: TextStyle(
        //   color: theme.colors.themeAccentDisabled,
        //   fontWeight: FontWeight.w600,
        //   height: 1.5,
        //   fontSize: 16,
        // ),
      ),
    );

    return ArDriveTheme(
      key: const ValueKey('turbo_payment_form'),
      themeData: textTheme,
      child: ScreenTypeLayout(
        mobile: _mobileView(context),
        desktop: _desktopView(context, textTheme.textFieldTheme),
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

  Widget _desktopView(BuildContext context, ArDriveTextFieldTheme theme) {
    return ArDriveDevToolsShortcuts(
      customShortcuts: [
        Shortcut(
          modifier: LogicalKeyboardKey.shiftLeft,
          key: LogicalKeyboardKey.keyT,
          action: () {
            ArDriveDevTools.instance.showDevTools(optionalContext: context);
          },
        )
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
                        child: ArDriveIcons.x()),
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
                    const SizedBox(height: 16),
                    BlocListener<PaymentFormBloc, PaymentFormState>(
                      listener: (context, state) {
                        logger.d('state: $state');
                        if (state is PaymentFormPopulatingFieldsForTesting) {
                          prePopulateWithHardcodedData();
                        }
                      },
                      child: ArDriveForm(
                        key: _formKey,
                        child: _formDesktop(
                          context,
                          theme,
                        ),
                      ),
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
  }

  /// TextFields
  ///
  Widget nameOnCardTextField() {
    return Expanded(
      child: ArDriveTextField(
        controller: _nameController,
        label: 'Name on Card',
        isFieldRequired: true,
        useErrorMessageOffset: true,
        onChanged: (s) {
          String valid = s.replaceAll(RegExp(r'[^a-zA-Z\s]'), '');
          _nameController.text = valid;
          _nameController.selection =
              TextSelection.collapsed(offset: valid.length);
        },
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
        controller: _cardNumberController,
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
        controller: _expiryDateController,
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

  Widget cvvTextField() {
    return Expanded(
      child: ArDriveTextField(
        controller: _cvvController,
        label: 'CVV',
        useErrorMessageOffset: true,
        validator: (s) {
          if (s == null || !validateCreditCardCVV(s, '4242 4242 4242 4242')) {
            return 'Please enter a valid CVV';
          }
          return null;
        },
        isFieldRequired: true,
        inputFormatters: [CreditCardCvcInputFormatter()],
      ),
    );
  }

  Widget countryTextField(ArDriveTextFieldTheme theme) {
    return Expanded(
      child: CountryInputDropdown(
        onChanged: (country) {
          setState(() {
            _selectedCountry = country;
          });
        },
        items: const [
          CountryItem('United States'),
        ],
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
            padding:
                //  ArDriveTheme.of(context)
                //     .themeData
                //     .textFieldTheme
                //     .contentPadding,
                const EdgeInsets.symmetric(
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
                      .themeAccentDisabled,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget stateTextField() {
    return Expanded(
      child: ArDriveTextField(
        controller: _stateController,
        label: 'State',
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

  Widget addressLine1TextField() {
    return Expanded(
      child: ArDriveTextField(
        controller: _addressLine1Controller,
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
        controller: _addressLine2Controller,
        label: 'Address Line 2',
        useErrorMessageOffset: true,
      ),
    );
  }

  Widget postalCodeTextField() {
    return Flexible(
      flex: 1,
      child: ArDriveTextField(
        controller: _postalCodeController,
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
    return const QuoteRefreshWidget();
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
                      '${winstonToAr(state.priceEstimate.credits).toStringAsFixed(6)} Credits',
                      style: ArDriveTypography.body.leadBold(),
                    );
                  },
                ),
                BlocBuilder<PaymentFormBloc, PaymentFormState>(
                  builder: (context, state) {
                    return RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text:
                                '\$${state.priceEstimate.priceInCurrency.toStringAsFixed(2)}',
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
                    );
                  },
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
            style: ArDriveTypography.body.captionBold(
              color:
                  ArDriveTheme.of(context).themeData.colors.themeAccentDisabled,
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
                context
                    .read<TurboTopupFlowBloc>()
                    .add(const TurboTopUpShowEstimationView());
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
            text: 'Review',
            fontStyle: ArDriveTypography.body.buttonLargeBold(
              color: Colors.white,
            ),
            isDisabled: !_isFormValid ||
                _selectedCountry == null ||
                !(card?.complete ?? false),
            onPressed: () {
              context.read<TurboTopupFlowBloc>().add(
                    TurboTopUpShowPaymentReviewView(
                      paymentUserInformation: PaymentUserInformationFromUSA(
                        addressLine1: _addressLine1Controller.text,
                        addressLine2: _addressLine2Controller.text,
                        cardNumber: _cardNumberController.text,
                        cvv: _cvvController.text,
                        expirationDate: _expiryDateController.text,
                        name: _nameController.text,
                        postalCode: _postalCodeController.text,
                        state: _stateController.text,
                      ),
                    ),
                  );
            },
          ),
        ],
      ),
    );
  }

  Widget _formDesktop(BuildContext context, ArDriveTextFieldTheme theme) {
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
          Padding(
            padding: const EdgeInsets.only(bottom: 4, right: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextFieldLabel(
                text: 'Credit Card *',
                style: ArDriveTypography.body.buttonNormalBold(
                  color: theme.requiredLabelColor,
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
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
          const SizedBox(
            height: 16,
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              countryTextField(theme),
              const SizedBox(width: 24),
              stateTextField(),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
    // if (textFieldState == TextFieldState.success) {
    //   return _getSuccessBorder(theme);
    // } else if (textFieldState == TextFieldState.error) {
    //   return _getErrorBorder(theme);
    // }

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
  final Widget Function(BuildContext context, int secondsLeft)? builder;

  const TimerWidget({
    super.key,
    required this.durationInSeconds,
    required this.onFinished,
    this.textStyle,
    this.builder,
  });

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
    return widget.builder != null
        ? widget.builder!(context, _secondsLeft)
        : Text(
            _formatDuration(_secondsLeft),
            style: widget.textStyle,
          );
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
    this.selectedItem,
    required this.buildSelectedItem,
    this.label,
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
  final Anchor anchor;
  final TextStyle? itemsTextStyle;

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
        anchor: widget.anchor,
        width: 200,
        items: widget.items
            .map(
              (e) => ArDriveDropdownItem(
                content: Center(
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
  const CountryInputDropdown({
    Key? key,
    required List<CountryItem> items,
    required Widget Function(CountryItem?) buildSelectedItem,
    CountryItem? selectedItem,
    required Function(CountryItem) onChanged,
  }) : super(
          key: key,
          items: items,
          selectedItem: selectedItem,
          buildSelectedItem: buildSelectedItem,
          label: 'Country *',
          onChanged: onChanged,
        );
}

class QuoteRefreshWidget extends StatefulWidget {
  const QuoteRefreshWidget({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _QuoteRefreshWidgetState createState() => _QuoteRefreshWidgetState();
}

class _QuoteRefreshWidgetState extends State<QuoteRefreshWidget> {
  @override
  Widget build(BuildContext context) {
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
              BlocBuilder<PaymentFormBloc, PaymentFormState>(
                builder: (context, state) {
                  return TimerWidget(
                    key: state is PaymentFormQuoteLoaded
                        ? const ValueKey('reset_timer')
                        : null,
                    durationInSeconds: 60 * 10,
                    onFinished: () {
                      logger.d('fetching quote');
                      context
                          .read<PaymentFormBloc>()
                          .add(PaymentFormUpdateQuote());
                    },
                  );
                },
              ),
            ],
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
                            .themeFgDisabled,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      // TODO: localize
                      Text(
                        'Refresh',
                        style: ArDriveTypography.body.captionBold(
                          color: ArDriveTheme.of(context)
                              .themeData
                              .colors
                              .themeFgDisabled,
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
    );
  }
}
