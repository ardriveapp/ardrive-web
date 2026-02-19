import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/cookie_policy_consent/cookie_policy_consent.dart';
import 'package:ardrive/cookie_policy_consent/views/cookie_policy_consent_modal.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/turbo/topup/blocs/topup_estimation_bloc.dart';
import 'package:ardrive/turbo/topup/blocs/turbo_topup_flow_bloc.dart';
import 'package:ardrive/turbo/topup/components/input_dropdown_menu.dart';
import 'package:ardrive/turbo/topup/components/turbo_topup_scaffold.dart';
import 'package:ardrive/turbo/topup/views/topup_modal.dart';
import 'package:ardrive/turbo/topup/views/unified/unified_crypto_flow.dart';
import 'package:ardrive/turbo/topup/views/turbo_error_view.dart';
import 'package:ardrive/turbo/utils/utils.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/file_size_units.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:responsive_builder/responsive_builder.dart';

const humanReadableNumberFormat = '#,##0';

class TopUpEstimationView extends StatefulWidget {
  const TopUpEstimationView({super.key});

  @override
  State<TopUpEstimationView> createState() => _TopUpEstimationViewState();
}

class _TopUpEstimationViewState extends State<TopUpEstimationView> {
  late TurboTopUpEstimationBloc paymentBloc;
  late Wallet wallet;

  @override
  initState() {
    super.initState();
    wallet =
        (context.read<ProfileCubit>().state as ProfileLoggedIn).user.wallet;
    paymentBloc = context.read<TurboTopUpEstimationBloc>();

    // Trigger initial data load after the first frame to avoid
    // dispatching events during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      paymentBloc.add(LoadInitialData());
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TurboTopUpEstimationBloc, TopupEstimationState>(
      bloc: paymentBloc,
      builder: (context, state) {
        if (state is EstimationLoading) {
          return const SizedBox(
            height: 575,
            child: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (state is EstimationLoaded) {
          return SingleChildScrollView(
            child: TurboTopupScaffold(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BalanceView(
                    balance: state.balance,
                    estimatedStorage: state.estimatedStorageForBalance,
                    fileSizeUnit: paymentBloc.currentDataUnit.name,
                  ),
                  const SizedBox(height: 20),
                  PresetAmountSelector(
                    amounts: presetAmounts,
                    currencyUnit: '\$',
                    preSelectedAmount: state.selectedAmount.toInt(),
                    onAmountSelected: (amount) {
                      paymentBloc.add(FiatAmountSelected(amount));
                    },
                    // Inline unit selector with amount label
                    trailingWidget: const UnitSelector(),
                  ),
                  const SizedBox(height: 16),
                  PriceEstimateView(
                    fiatAmount: state.selectedAmount,
                    fiatCurrency: '\$',
                    estimatedCredits: state.creditsForSelectedAmount,
                    estimatedStorage: state.estimatedStorageForSelectedAmount,
                    storageUnit: paymentBloc.currentDataUnit.abbreviation,
                  ),
                  const SizedBox(height: 20),
                  // Payment method buttons - side by side
                  _PaymentMethodButtons(
                    isDisabled: paymentBloc.currentAmount == 0 ||
                        state is EstimationLoading ||
                        state is EstimationLoadError,
                  ),
                ],
              ),
            ),
          );
        } else if (state is FetchEstimationError || state is EstimationLoadError) {
          return TurboErrorView(
            errorType: TurboErrorType.fetchEstimationInformationFailed,
            onDismiss: () {},
            onTryAgain: () {
              paymentBloc.add(LoadInitialData());
            },
          );
        } else if (state is EstimationInitial) {
          // Initial state - data load is triggered in initState
          return const SizedBox(
            height: 575,
            child: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }
        // Default fallback for any unhandled state - show loading
        return const SizedBox(
          height: 575,
          child: Center(
            child: CircularProgressIndicator(),
          ),
        );
      },
    );
  }

}

/// Payment method buttons for Card and Crypto
class _PaymentMethodButtons extends StatelessWidget {
  final bool isDisabled;

  const _PaymentMethodButtons({
    required this.isDisabled,
  });

  @override
  Widget build(BuildContext context) {
    return ScreenTypeLayout.builder(
      mobile: (context) => Column(
        children: [
          // Pay with Card button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: _CardPaymentButton(isDisabled: isDisabled),
          ),
          const SizedBox(height: 12),
          // Pay with Crypto button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: _CryptoPaymentButton(isDisabled: isDisabled),
          ),
        ],
      ),
      desktop: (context) => Row(
        children: [
          // Pay with Card button
          Expanded(
            child: SizedBox(
              height: 48,
              child: _CardPaymentButton(isDisabled: isDisabled),
            ),
          ),
          const SizedBox(width: 16),
          // Pay with Crypto button
          Expanded(
            child: SizedBox(
              height: 48,
              child: _CryptoPaymentButton(isDisabled: isDisabled),
            ),
          ),
        ],
      ),
    );
  }
}

/// Card payment button with cookie consent
/// Note: Card payments require a minimum of $5 (minCardAmount)
class _CardPaymentButton extends StatelessWidget {
  final bool isDisabled;

  const _CardPaymentButton({required this.isDisabled});

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final estimationBloc = context.read<TurboTopUpEstimationBloc>();
    final amount = estimationBloc.currentAmount;

    // Card payments require minimum $5
    final isBelowMinimum = amount < minCardAmount;
    final buttonDisabled = isDisabled || isBelowMinimum;

    // For disabled state, use themeFgMuted for better contrast against themeAccentDisabled background
    final textColor = buttonDisabled ? colors.themeFgMuted : colors.themeFgOnAccent;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ArDriveButton(
          isDisabled: buttonDisabled,
          icon: Icon(
            Icons.credit_card,
            size: 18,
            color: textColor,
          ),
          text: 'Pay with Card',
          fontStyle: ArDriveTypographyNew.of(context).paragraphLarge(
            fontWeight: ArFontWeight.bold,
            color: textColor,
          ),
          onPressed: () async {
            // Check cookie consent before proceeding to card payment
            final cookieConsent = ArDriveCookiePolicyConsent();
            final hasConsent = await cookieConsent.hasAcceptedCookiePolicy();

            if (!context.mounted) return;

            if (hasConsent) {
              // Already has consent, proceed directly
              context
                  .read<TurboTopupFlowBloc>()
                  .add(const TurboTopUpShowPaymentFormView(4));
            } else {
              // Show cookie consent modal, then proceed if accepted
              showCookiePolicyConsentModal(context, (ctx) {
                ctx.read<TurboTopupFlowBloc>().add(
                      const TurboTopUpShowPaymentFormView(4),
                    );
              });
            }
          },
        ),
        if (isBelowMinimum && !isDisabled)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '\$${minCardAmount.toStringAsFixed(0)} minimum',
              style: ArDriveTypographyNew.of(context).paragraphSmall(
                color: colors.themeFgMuted,
              ),
            ),
          ),
      ],
    );
  }
}

/// Crypto payment button
class _CryptoPaymentButton extends StatelessWidget {
  final bool isDisabled;

  const _CryptoPaymentButton({required this.isDisabled});

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    return ArDriveButton(
      isDisabled: isDisabled,
      style: ArDriveButtonStyle.secondary,
      icon: Icon(
        Icons.currency_bitcoin,
        size: 18,
        color: isDisabled ? colors.themeFgDisabled : colors.themeFgDefault,
      ),
      text: 'Pay with Crypto',
      fontStyle: ArDriveTypographyNew.of(context).paragraphLarge(
        fontWeight: ArFontWeight.bold,
        color: isDisabled ? colors.themeFgDisabled : colors.themeFgDefault,
      ),
      onPressed: () {
        _openCryptoModal(context);
      },
    );
  }

  Future<void> _openCryptoModal(BuildContext context) async {
    // Get the current selected amount from the estimation bloc
    final estimationBloc = context.read<TurboTopUpEstimationBloc>();
    final fiatAmount = estimationBloc.currentAmount;

    // Close the current turbo modal
    Navigator.of(context).pop();

    // Small delay for animation
    await Future.delayed(const Duration(milliseconds: 100));

    // Show the new unified crypto flow
    if (context.mounted) {
      await showUnifiedCryptoModal(
        context,
        fiatAmount: fiatAmount,
        onBackToPaymentMethods: () {
          // Reopen the turbo modal when back is pressed
          if (context.mounted) {
            showTurboTopupModal(context);
          }
        },
      );
    }
  }
}

class UnitSelector extends StatelessWidget {
  const UnitSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final paymentBloc = context.read<TurboTopUpEstimationBloc>();

    return Row(
      children: [
        CurrencyDropdownMenu(
          label: appLocalizationsOf(context).currency,
          itemsTextStyle: ArDriveTypographyNew.of(context).caption(
            fontWeight: ArFontWeight.bold,
          ),
          items: [
            CurrencyItem('USD'),
          ],
          buildSelectedItem: (item) => Row(
            children: [
              Text(
                item?.label ?? 'USD',
                style: ArDriveTypographyNew.of(context).paragraphNormal(
                  fontWeight: ArFontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              ArDriveIcons.carretDown(size: 16),
            ],
          ),
        ),
        const SizedBox(
          width: 40,
        ),
        UnitDropdownMenu(
          label: appLocalizationsOf(context).units,
          itemsTextStyle: ArDriveTypographyNew.of(context).caption(
            fontWeight: ArFontWeight.bold,
          ),
          items: FileSizeUnit.values
              .map(
                (unit) => UnitItem(unit),
              )
              .toList(),
          buildSelectedItem: (item) => Row(
            children: [
              Text(
                item?.label ?? 'GB',
                style: ArDriveTypographyNew.of(context).paragraphNormal(
                  fontWeight: ArFontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              ArDriveIcons.carretDown(size: 16),
            ],
          ),
          onChanged: (value) {
            paymentBloc.add(
              DataUnitChanged(value.unit),
            );
          },
        ),
      ],
    );
  }
}

class PresetAmountSelector extends StatefulWidget {
  final List<int> amounts;
  final String currencyUnit;
  final int preSelectedAmount;
  final Function(double) onAmountSelected;
  final Widget? trailingWidget;
  const PresetAmountSelector({
    super.key,
    required this.amounts,
    required this.currencyUnit,
    required this.preSelectedAmount,
    required this.onAmountSelected,
    this.trailingWidget,
  });

  @override
  State<PresetAmountSelector> createState() => _PresetAmountSelectorState();
}

class _PresetAmountSelectorState extends State<PresetAmountSelector> {
  final TextEditingController _customAmountController = TextEditingController();
  late FocusNode _customAmountFocus;
  late GlobalKey<ArDriveFormState> _formKey;
  int selectedAmount = 0;
  String? _customAmountValidationMessage;

  @override
  void initState() {
    selectedAmount = widget.preSelectedAmount;
    _formKey = GlobalKey<ArDriveFormState>();
    _customAmountFocus = FocusNode();
    // add post frame callback to set the focus on the custom amount field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<TurboTopUpEstimationBloc>().state;

      if (state is EstimationLoaded) {
        setState(() {
          if (!presetAmounts.contains(state.selectedAmount)) {
            _customAmountController.text = state.selectedAmount.toString();
          }
        });
      }
    });

    super.initState();
  }

  void _onAmountChanged(String amount) {
    widget.onAmountSelected(double.parse(amount));
  }

  void _onPresetAmountSelected(int amount) {
    setState(() {
      selectedAmount = amount;
    });

    _onAmountChanged(amount.toString());
  }

  void _onCustomAmountSelected(String amount) {
    int amountInt = int.tryParse(amount) ?? 0;

    // Selects zero to disable the button
    if (amount.isEmpty || amountInt < minAmount) {
      amountInt = 0;
    }

    setState(() {
      selectedAmount = amountInt;
    });

    _onAmountChanged(amountInt.toString());
  }

  void _resetCustomAmount() {
    setState(() {
      _customAmountController.text = '';
      _customAmountValidationMessage = null;
      _formKey.currentState?.validate();
      _customAmountFocus.unfocus();
    });
  }

  Widget buildButtonBar(BuildContext context, ArDriveThemeData textTheme) {
    buildButtons(double height, double width) => widget.amounts
        .map(
          (amount) => Flexible(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ArDriveButton(
                backgroundColor: selectedAmount == amount
                    ? ArDriveTheme.of(context).themeData.colors.themeFgMuted
                    : ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeBorderDefault,
                style: ArDriveButtonStyle.primary,
                maxHeight: height,
                maxWidth: width,
                fontStyle: ArDriveTypographyNew.of(context).paragraphSmall(
                  fontWeight: ArFontWeight.bold,
                  color: selectedAmount == amount
                      ? ArDriveTheme.of(context).themeData.colors.themeBgSurface
                      : ArDriveTheme.of(context).themeData.colors.themeFgMuted,
                ),
                text: '${widget.currencyUnit}$amount',
                onPressed: () {
                  _onPresetAmountSelected(amount);
                  _resetCustomAmount();
                },
              ),
            ),
          ),
        )
        .toList();

    // Always show inline layout (modal is fixed width, not responsive)
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        ...buildButtons(40, 90),
        // Custom amount input inline with preset buttons
        Flexible(
          flex: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _customAmountTextField(textTheme, compact: true),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ArDriveTheme.of(context).themeData;

    // custom theme for the text fields on the top-up form
    final textTheme = theme.copyWith(
      textFieldTheme: theme.textFieldTheme.copyWith(
        inputBackgroundColor: theme.colors.themeBgCanvas,
        labelColor: theme.colors.themeFgDefault,
        requiredLabelColor: theme.colors.themeFgDefault,
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
          color: theme.colors.themeFgDefault,
          fontWeight: FontWeight.w600,
          height: 1.5,
          fontSize: 16,
        ),
      ),
    );
    final typography = ArDriveTypographyNew.of(context);

    return ArDriveForm(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                appLocalizationsOf(context).amount,
                style: typography.paragraphNormal(
                  fontWeight: ArFontWeight.bold,
                  color: ArDriveTheme.of(context).themeData.colors.themeFgMuted,
                ),
              ),
              if (widget.trailingWidget != null) widget.trailingWidget!,
            ],
          ),
          const SizedBox(height: 12),
          buildButtonBar(context, textTheme),
          // Show validation message if there's an error
          if (_customAmountValidationMessage != null &&
              _customAmountValidationMessage!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: AnimatedFeedbackMessage(
                text: _customAmountValidationMessage!,
              ),
            )
        ],
      ),
    );
  }

  Widget _customAmountTextField(textTheme, {bool compact = false}) {
    return SizedBox(
      key: const ValueKey('custom_amount_text_field'),
      width: compact ? null : 114,
      height: compact ? 40 : null,
      child: ArDriveTheme(
        themeData: textTheme,
        child: ArDriveTextField(
          focusNode: _customAmountFocus,
          controller: _customAmountController,
          showErrorMessage: false,
          hintText: compact ? 'Custom' : null,
          preffix: Text(
            '\$ ',
            style: ArDriveTypographyNew.of(context).paragraphLarge(
              fontWeight: ArFontWeight.bold,
              color: ArDriveTheme.of(context).themeData.colors.themeFgDefault,
            ),
          ),
          autovalidateMode: AutovalidateMode.disabled,
          validator: (s) {
            setState(() {
              if (s == null || s.isEmpty) {
                _customAmountValidationMessage = null;
                _onCustomAmountSelected('');
                return;
              }

              String? errorMessage;

              final numValue = int.tryParse(s);

              if (numValue == null ||
                  numValue < minAmount ||
                  numValue > maxAmount) {
                errorMessage = _pleaseEnterAnAmountBetweenText;
              }

              _customAmountValidationMessage = errorMessage;

              _onCustomAmountSelected(s);
            });

            return _customAmountValidationMessage;
          },
          keyboardType: TextInputType.number,
          inputFormatters: [
            TextInputFormatter.withFunction((oldValue, newValue) {
              String newValueText = newValue.text
                  // Remove any non-digit character
                  .replaceAll(RegExp(r'\D'), '')
                  // Replace multiple zeroes with a single one
                  .replaceAll(RegExp(r'^0+$'), '0')
                  // Remove any leading zeroes
                  .replaceAll(RegExp(r'^0+(?=[^0])'), '');

              if (newValueText.isNotEmpty) {
                int valueAsInt = int.parse(newValueText);
                if (valueAsInt > maxAmount) {
                  // If the value is greater than the max amount, truncate the
                  /// last digit and place the cursor at the end
                  String newString =
                      newValueText.substring(0, newValueText.length - 1);
                  return TextEditingValue(
                    text: newString,
                    selection:
                        TextSelection.collapsed(offset: newString.length),
                  );
                }
              }
              return TextEditingValue(
                text: newValueText,
                selection: TextSelection.collapsed(offset: newValueText.length),
              );
            }),
          ],
        ),
      ),
    );
  }

  String get _pleaseEnterAnAmountBetweenText {
    return appLocalizationsOf(context).turboPleaseEnterAmountBetween(
      '\$$_formattedMaxAmount',
      '\$$_formattedMinAmount',
    );
  }

  String get _formattedMinAmount {
    return NumberFormat(humanReadableNumberFormat).format(minAmount);
  }

  String get _formattedMaxAmount {
    return NumberFormat(humanReadableNumberFormat).format(maxAmount);
  }
}

class _BalanceView extends StatefulWidget {
  final BigInt balance;
  final String estimatedStorage;
  final String fileSizeUnit;

  const _BalanceView({
    required this.balance,
    required this.estimatedStorage,
    required this.fileSizeUnit,
  });

  @override
  State<_BalanceView> createState() => _BalanceViewState();
}

class _BalanceViewState extends State<_BalanceView> {
  List<Widget> balanceContents(bool isMobile, ArdriveTypographyNew typography) => [
        Flexible(
          flex: 1,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                appLocalizationsOf(context).arBalance,
                style: typography.paragraphSmall(fontWeight: ArFontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                '${convertWinstonToLiteralString(widget.balance)} ${appLocalizationsOf(context).credits}',
                style: typography.paragraphLarge(
                  fontWeight: ArFontWeight.bold,
                  color: ArDriveTheme.of(context).themeData.colors.themeFgMuted,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: isMobile ? 24 : 0,
          width: isMobile ? 0 : 32,
        ),
        Flexible(
          flex: 1,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                appLocalizationsOf(context).estimatedStorage,
                style: typography.paragraphSmall(fontWeight: ArFontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.estimatedStorage} ${widget.fileSizeUnit}',
                style: typography.paragraphLarge(
                  fontWeight: ArFontWeight.bold,
                  color: ArDriveTheme.of(context).themeData.colors.themeFgMuted,
                ),
              ),
            ],
          ),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    return ScreenTypeLayout.builder(
      desktop: (context) => Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: balanceContents(false, typography),
      ),
      mobile: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: balanceContents(true, typography),
      ),
    );
  }
}

class PriceEstimateView extends StatelessWidget {
  final double fiatAmount;
  final String fiatCurrency;
  final BigInt estimatedCredits;
  final String estimatedStorage;
  final String storageUnit;

  const PriceEstimateView({
    super.key,
    required this.fiatAmount,
    required this.fiatCurrency,
    required this.estimatedCredits,
    required this.estimatedStorage,
    required this.storageUnit,
  });

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    return BlocBuilder<TurboTopUpEstimationBloc, TopupEstimationState>(
      buildWhen: (previous, current) {
        return current is EstimationLoaded || current is EstimationLoadError;
      },
      builder: (context, state) {
        if (state is EstimationLoadError) {
          return Text(
            appLocalizationsOf(context).unableToFetchEstimateAtThisTime,
            style: typography.paragraphNormal(
              fontWeight: ArFontWeight.bold,
              color: ArDriveTheme.of(context)
                  .themeData
                  .colors
                  .themeErrorDefault,
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '$fiatCurrency $fiatAmount = ${convertWinstonToLiteralString(estimatedCredits)} ${appLocalizationsOf(context).credits}',
                  style: typography.paragraphNormal(fontWeight: ArFontWeight.bold),
                ),
                Transform.translate(
                  offset: const Offset(0, 4),
                  child: Text(
                    ' ~ ',
                    style: typography.paragraphNormal(fontWeight: ArFontWeight.bold),
                  ),
                ),
                Text(
                  '$estimatedStorage $storageUnit',
                  style: typography.paragraphNormal(fontWeight: ArFontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ArDriveClickArea(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text.rich(
                    TextSpan(
                      text: appLocalizationsOf(context)
                          .howAreConversionsDetermined,
                      style: typography.paragraphNormal(
                        fontWeight: ArFontWeight.bold,
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgMuted,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => openUrl(
                              url: Resources.howAreConversionsDetermined,
                            ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(top: 2.0),
                    child: ArDriveIcons.newWindow(
                      color: ArDriveTheme.of(context)
                          .themeData
                          .colors
                          .themeFgMuted,
                      size: 16,
                    ),
                  )
                ],
              ),
            ),
            const Divider(height: 32),
          ],
        );
      },
    );
  }
}

class CurrencyDropdownMenu extends InputDropdownMenu<CurrencyItem> {
  const CurrencyDropdownMenu({
    super.key,
    required super.items,
    required super.buildSelectedItem,
    required super.label,
    super.onChanged,
    super.anchor = const Aligned(
      follower: Alignment.bottomLeft,
      target: Alignment.topLeft,
      offset: Offset(
        0,
        4,
      ),
    ),
    super.itemsTextStyle,
  });
}

class CurrencyItem extends InputDropdownItem {
  CurrencyItem(super.label);
}

class UnitDropdownMenu extends InputDropdownMenu<UnitItem> {
  const UnitDropdownMenu({
    super.key,
    required super.items,
    required super.buildSelectedItem,
    required super.label,
    super.onChanged,
    super.anchor = const Aligned(
      follower: Alignment.bottomLeft,
      target: Alignment.topLeft,
      offset: Offset(
        0,
        4,
      ),
    ),
    super.itemsTextStyle,
  });
}

class UnitItem extends InputDropdownItem {
  final FileSizeUnit unit;

  UnitItem(this.unit) : super(unit.name);
}

class AnimatedFeedbackMessage extends StatefulWidget {
  final String text;

  const AnimatedFeedbackMessage({super.key, required this.text});

  @override
  AnimatedFeedbackMessageState createState() => AnimatedFeedbackMessageState();
}

class AnimatedFeedbackMessageState extends State<AnimatedFeedbackMessage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _animation = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.fastLinearToSlowEaseIn,
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScreenTypeLayout.builder(
      mobile: (_) => AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return ClipRect(
            clipper: _CustomClipper(_animation.value, ArrowSide.bottomLeft),
            child: child,
          );
        },
        child: FeedbackMessage(
          text: widget.text,
          arrowSide: ArrowSide.bottomLeft,
          height: 50,
          borderColor:
              ArDriveTheme.of(context).themeData.colors.themeErrorSubtle,
          backgroundColor:
              ArDriveTheme.of(context).themeData.colors.themeErrorSubtle,
        ),
      ),
      desktop: (context) {
        return AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            return ClipRect(
              clipper: _CustomClipper(_animation.value, ArrowSide.left),
              child: child,
            );
          },
          child: FeedbackMessage(
            text: widget.text,
            arrowSide: ArrowSide.right,
            height: 48,
            borderColor:
                ArDriveTheme.of(context).themeData.colors.themeErrorSubtle,
            backgroundColor:
                ArDriveTheme.of(context).themeData.colors.themeErrorSubtle,
          ),
        );
      },
    );
  }
}

class _CustomClipper extends CustomClipper<Rect> {
  final ArrowSide arrowSide;

  final double progress;

  _CustomClipper(this.progress, this.arrowSide);

  @override
  Rect getClip(Size size) {
    if (arrowSide == ArrowSide.bottomLeft) {
      return Rect.fromLTWH(
          0, size.height * (1 - progress), size.width, size.height);
    }
    return Rect.fromLTWH(0, 0, size.width * progress, size.height);
  }

  @override
  bool shouldReclip(CustomClipper<Rect> oldClipper) {
    return true;
  }
}
