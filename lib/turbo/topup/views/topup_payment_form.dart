import 'package:ardrive/components/keyboard_handler.dart';
import 'package:ardrive/dev_tools/app_dev_tools.dart';
import 'package:ardrive/dev_tools/shortcut_handler.dart';
import 'package:ardrive/turbo/topup/blocs/payment_form/payment_form_bloc.dart';
import 'package:ardrive/turbo/topup/blocs/topup_estimation_bloc.dart';
import 'package:ardrive/turbo/topup/blocs/turbo_topup_flow_bloc.dart';
import 'package:ardrive/turbo/topup/components/country_picker.dart';
import 'package:ardrive/turbo/topup/components/quote_timer.dart';
import 'package:ardrive/turbo/topup/components/stripe_card_colors.dart';
import 'package:ardrive/turbo/topup/components/turbo_topup_scaffold.dart';
import 'package:ardrive/turbo/topup/views/turbo_error_view.dart';
import 'package:ardrive/turbo/utils/utils.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
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
        requiredLabelColor: theme.colorTokens.textHigh,
        labelColor: theme.colorTokens.textHigh,
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
    return _scaffold(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: _quoteTimer(),
          ),
          const SizedBox(height: 8),
          _credits(context),
          const SizedBox(height: 24),
          _formDesktop(context, theme),
        ],
      ),
    );
  }

  /// The screen's dialog: its title, the Stripe line, and Back and Review in
  /// the action row.
  Widget _scaffold(BuildContext context, {required Widget child}) {
    final canReview = _selectedCountry != null &&
        _nameController.text.isNotEmpty &&
        (card?.complete ?? false);

    return TurboTopupScaffold(
      title: appLocalizationsOf(context).paymentDetails,
      description:
          appLocalizationsOf(context).thisIsAOneTimePaymentPoweredByStripe,
      actions: [
        ModalAction.dismiss(
          title: appLocalizationsOf(context).back,
          action: () => context
              .read<TurboTopupFlowBloc>()
              .add(const TurboTopUpShowEstimationView()),
        ),
        ModalAction(
          title: appLocalizationsOf(context).review,
          isEnable: canReview,
          action: () => context.read<TurboTopupFlowBloc>().add(
                TurboTopUpShowPaymentReviewView(
                  name: _nameController.text,
                  country: _selectedCountry!.label,
                ),
              ),
        ),
      ],
      child: child,
    );
  }

  Widget _desktopView(BuildContext context, ArDriveTextFieldTheme theme) {
    return BlocListener<PaymentFormBloc, PaymentFormState>(
      listener: (context, state) {
        if (state is PaymentFormError) {
          showArDriveDialog(
            context,
            barrierDismissible: false,
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
          );
        }
      },
      child: BlocBuilder<PaymentFormBloc, PaymentFormState>(
        builder: (context, state) {
          if (state is PaymentFormLoading) {
            return TurboTopupScaffold(
              title: appLocalizationsOf(context).paymentDetails,
              child: const SizedBox(
                height: 400,
                child: Center(
                  child: ArDriveSpinner(size: ArDriveSpinnerSize.large),
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
            child: _scaffold(
              context,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The quote's timer, as on the review.
                  Align(
                    alignment: Alignment.centerRight,
                    child: _quoteTimer(),
                  ),
                  const SizedBox(height: 8),
                  _credits(context),
                  const SizedBox(height: 24),
                  _formDesktop(context, theme),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// The quote's countdown, refreshed when it runs out or when asked.
  Widget _quoteTimer() {
    return BlocBuilder<PaymentFormBloc, PaymentFormState>(
      builder: (context, state) {
        final bloc = context.read<PaymentFormBloc>();
        final failed = state is PaymentFormQuoteLoadFailure;

        return QuoteTimer(
          // A new quote restarts the countdown, even with the same length.
          key: state is PaymentFormQuoteLoaded
              ? const ValueKey('reset_timer')
              : null,
          secondsLeft: state.quoteExpirationTimeInSeconds,
          isLoading: state is PaymentFormLoadingQuote,
          errorMessage:
              failed ? appLocalizationsOf(context).unableToUpdateQuote : null,
          onRefresh: () => bloc.add(PaymentFormUpdateQuote()),
          onExpired: failed ? null : () => bloc.add(PaymentFormUpdateQuote()),
        );
      },
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
                // The credits being bought are the screen's figure.
                BlocBuilder<PaymentFormBloc, PaymentFormState>(
                  builder: (context, state) {
                    final typography = ArDriveTypographyNew.of(context);
                    final colorTokens =
                        ArDriveTheme.of(context).themeData.colorTokens;

                    return Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: convertWinstonToLiteralString(
                              state.winstonCredits,
                            ),
                            style: typography.heading2(
                              color: colorTokens.textHigh,
                              fontWeight: ArFontWeight.light,
                            ),
                          ),
                          TextSpan(
                            text: ' credits',
                            style: typography.paragraphLarge(
                              color: colorTokens.textMid,
                              fontWeight: ArFontWeight.semiBold,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                BlocBuilder<PaymentFormBloc, PaymentFormState>(
                  builder: (context, state) {
                    return RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '\$${state.paymentAmount}',
                            style: ArDriveTypographyNew.of(context)
                                .paragraphNormal(
                              fontWeight: ArFontWeight.semiBold,
                              color: ArDriveTheme.of(context)
                                  .themeData
                                  .colorTokens
                                  .textMid,
                            ),
                          ),
                          if (state.hasPromoCodeApplied)
                            _buildDiscountText(context, state),
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

  TextSpan _buildDiscountText(BuildContext context, PaymentFormState state) {
    final String text;
    final hasReachedMaximumDiscount = state.hasReachedMaximumDiscount;

    if (hasReachedMaximumDiscount) {
      text = appLocalizationsOf(context).turboUsdDiscountApplied(
        state.adjustmentAmount!,
      );
    } else {
      text = appLocalizationsOf(context).turboPercentageDiscountApplied(
        state.humanReadableDiscountPercentage!,
      );
    }

    return TextSpan(
      text: ' $text',
      style: ArDriveTypographyNew.of(context).paragraphNormal(
        color: ArDriveTheme.of(context).themeData.colorTokens.textXLow,
      ),
    );
  }

  Widget _formDesktop(BuildContext context, ArDriveTextFieldTheme theme) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    applyStripeCardColors(
      text: colorTokens.textHigh,
      placeholder: colorTokens.textXLow,
      icon: colorTokens.textMid,
      error: colorTokens.statusErrorFg,
    );

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
                text: '${appLocalizationsOf(context).creditCard} *',
                // The standard field label, as on Name on card.
                style: ArDriveTypographyNew.of(context).paragraphNormal(
                  fontWeight: ArFontWeight.semiBold,
                  color: ArDriveTheme.of(context).themeData.colorTokens.textLow,
                ),
              ),
            ),
          ),
          // Drawn like the standard text field above it, in both themes.
          // The text inside lives in Stripe's iframe; it takes its colours
          // from applyStripeCardColors.
          CardField(
            style: ArDriveTypographyNew.of(context).paragraphNormal(
              color: colorTokens.textHigh,
            ),
            cursorColor: colorTokens.textHigh,
            decoration: InputDecoration(
              filled: true,
              fillColor: colorTokens.inputDefault,
              enabledBorder: _border(colorTokens.strokeMid),
              focusedBorder: _border(colorTokens.strokeHigh),
              errorBorder: _border(colorTokens.strokeRed),
              disabledBorder: _border(colorTokens.strokeMid),
              hintStyle: TextStyle(color: colorTokens.textXLow),
              // CardField draws its own box 23 px tall at 14 px text; 13 px
              // above and below makes it as tall as the name field's 49.
              contentPadding: const EdgeInsets.fromLTRB(20, 13, 20, 13),
            ),
            onCardChanged: (c) {
              setState(() {
                card = c;
              });
            },
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              countryTextField(theme),
            ],
          ),
        ],
      ),
    );
  }

  Widget nameOnCardTextField() {
    return Expanded(
      child: ArDriveTextFieldNew(
        controller: _nameController,
        label: appLocalizationsOf(context).nameOnCard,
        isFieldRequired: true,
        useErrorMessageOffset: true,
        inputFormatters: [
          // Only allow letters and spaces for name
          FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]')),
        ],
        onChanged: (_) {
          // Trigger rebuild to update button state
          setState(() {});
        },
        validator: (s) {
          if (s == null || s.isEmpty) {
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
            child: CountryPicker(
              label: appLocalizationsOf(context).country,
              countries: state.supportedCountries,
              onChanged: (country) {
                setState(() {
                  _selectedCountry =
                      country == null ? null : CountryItem(country);
                });
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
      'Promo code', // TODO: localize
      style: ArDriveTypographyNew.of(context).paragraphNormal(
        fontWeight: ArFontWeight.bold,
        color: ArDriveTheme.of(context).themeData.colorTokens.textHigh,
      ),
    );
  }

  Widget promoCodeWidget(ArDriveTextFieldTheme theme) {
    return BlocBuilder<PaymentFormBloc, PaymentFormState>(
        builder: (context, state) {
      final hasPromoCodeApplied = state.hasPromoCodeApplied;

      return Expanded(
        child: hasPromoCodeApplied
            ? promoCodeAppliedWidget(theme)
            : promoCodeTextField(),
      );
    });
  }

  Widget promoCodeAppliedWidget(ArDriveTextFieldTheme theme) {
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
                style: ArDriveTypographyNew.of(context).paragraphNormal(
                  fontWeight: ArFontWeight.bold,
                  color:
                      ArDriveTheme.of(context).themeData.colorTokens.textHigh,
                ),
              ),
            ),
          ),
        ),
        GestureDetector(
          onTap: () {
            setState(() {
              _promoCodeController.clear();
              paymentFormBloc.add(const PaymentFormUpdatePromoCode(null));
            });
          },
          child: ArDriveTooltip(
            message: 'Remove promo code', // TODO: localize
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: ArDriveIcons.closeCircle(
                color: ArDriveTheme.of(context).themeData.colorTokens.textMid,
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
        if (state is PaymentFormLoaded) {
          setState(() {
            _promoCodeInvalid = state.isPromoCodeInvalid;
            _errorFetchingPromoCode = state.errorFetchingPromoCode;

            final isFetchingPromoCode = state.isFetchingPromoCode;

            if (_promoCodeInvalid) {
              _promoCodeController.clear();
            }

            if (!_promoCodeInvalid &&
                !_errorFetchingPromoCode &&
                !isFetchingPromoCode) {
              final estimationBloc = context.read<TurboTopUpEstimationBloc>();
              estimationBloc.add(const PromoCodeChanged());
            }
          });
        }
      },
      builder: (context, state) {
        final promoCodeFetching =
            state is PaymentFormLoaded ? state.isFetchingPromoCode : false;

        return ArDriveTextFieldNew(
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
      return const ArDriveSpinner();
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
            style: ArDriveTypographyNew.of(context).paragraphNormal(
              fontWeight: ArFontWeight.bold,
              color: ArDriveTheme.of(context).themeData.colorTokens.textHigh,
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
    paymentFormBloc.add(PaymentFormUpdatePromoCode(_promoCodeController.text));
  }

  /// The standard text field's edge, so the card field matches its
  /// neighbours.
  InputBorder _border(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(ArDriveRadius.control),
      borderSide: BorderSide(color: color, width: 1),
    );
  }
}

/// A country offered for the card's billing address.
class CountryItem {
  final String label;

  const CountryItem(this.label);
}
