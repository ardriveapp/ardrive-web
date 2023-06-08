import 'dart:async';

import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/turbo/topup/blocs/topup_estimation_bloc.dart';
import 'package:ardrive/turbo/topup/components/input_dropdown_menu.dart';
import 'package:ardrive/turbo/topup/components/turbo_topup_scaffold.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/file_size_units.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:responsive_builder/responsive_builder.dart';

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
    wallet = (context.read<ProfileCubit>().state as ProfileLoggedIn).wallet;

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final paymentBloc = context.read<TurboTopUpEstimationBloc>();

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
        } else if (state is EstimationLoaded) {
          return SingleChildScrollView(
            child: TurboTopupScaffold(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      SvgPicture.asset(
                        Resources.images.brand.turbo,
                        height: 30,
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgDefault,
                        colorBlendMode: BlendMode.srcIn,
                        fit: BoxFit.contain,
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  _BalanceView(
                    balance: state.balance,
                    estimatedStorage: state.estimatedStorageForBalance,
                    fileSizeUnit: paymentBloc.currentDataUnit.name,
                  ),
                  const SizedBox(height: 40),
                  PresetAmountSelector(
                    amounts: presetAmounts,
                    currencyUnit: '\$',
                    preSelectedAmount: state.selectedAmount.toInt(),
                    onAmountSelected: (amount) {
                      paymentBloc.add(FiatAmountSelected(amount));
                    },
                  ),
                  const SizedBox(height: 24),
                  PriceEstimateView(
                    fiatAmount: state.selectedAmount.toInt(),
                    fiatCurrency: '\$',
                    estimatedCredits: state.creditsForSelectedAmount,
                    estimatedStorage: state.estimatedStorageForSelectedAmount,
                    storageUnit: paymentBloc.currentDataUnit.name,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            CurrencyDropdownMenu(
                              itemsTextStyle:
                                  ArDriveTypography.body.captionBold(),
                              items: [
                                CurrencyItem('USD'),
                              ],
                              buildSelectedItem: (item) => Row(
                                children: [
                                  Text(
                                    item?.label ?? 'USD',
                                    style: ArDriveTypography.body
                                        .buttonNormalBold(),
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
                              itemsTextStyle:
                                  ArDriveTypography.body.captionBold(),
                              items: FileSizeUnit.values
                                  .map(
                                    (unit) => UnitItem(unit),
                                  )
                                  .toList(),
                              buildSelectedItem: (item) => Row(
                                children: [
                                  Text(
                                    item?.label ?? 'GB',
                                    style: ArDriveTypography.body
                                        .buttonNormalBold(),
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
                        ),
                      ),
                      ArDriveButton(
                        isDisabled: paymentBloc.currentAmount == 0,
                        maxWidth: 143,
                        maxHeight: 40,
                        fontStyle: ArDriveTypography.body
                            .buttonLargeBold()
                            .copyWith(fontWeight: FontWeight.w700),
                        text: appLocalizationsOf(context).next,
                        onPressed: () {
                          // Go to the paumentFormView.
                          // Will be implemented in the next PR.
                          // context
                          //     .read<TurboTopupFlowBloc>()
                          //     .add(const TurboTopUpShowPaymentFormView());
                        },
                      ),
                    ],
                  )
                ],
              ),
            ),
          );
        } else if (state is EstimationError) {
          return TurboTopupScaffold(
            child: SizedBox(
              height: 575,
              child: Center(
                child: Text(appLocalizationsOf(context).error),
              ),
            ),
          );
        }
        return TurboTopupScaffold(
          child: Container(
            height: 650,
            color: ArDriveTheme.of(context).themeData.colors.themeBgCanvas,
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          ),
        );
      },
    );
  }
}

class PresetAmountSelector extends StatefulWidget {
  final List<int> amounts;
  final String currencyUnit;
  final int preSelectedAmount;
  final Function(int) onAmountSelected;
  const PresetAmountSelector({
    super.key,
    required this.amounts,
    required this.currencyUnit,
    required this.preSelectedAmount,
    required this.onAmountSelected,
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

    super.initState();
  }

  DateTime lastChanged = DateTime.now();

  Timer? _timer;

  void _onAmountChanged(String amount) {
    if (_timer != null && _timer!.isActive) {
      _timer?.cancel();
    }
    _timer = Timer(const Duration(milliseconds: 500), () {
      widget.onAmountSelected(int.parse(amount));
    });
  }

  void _onPresetAmountSelected(int amount) {
    setState(() {
      selectedAmount = amount;
    });

    _onAmountChanged(amount.toString());
  }

  void _onCustomAmountSelected(String amount) {
    int amountInt = int.parse(amount);

    // Selects zero to disable the button
    if (amount.isEmpty || amountInt < 10) {
      amountInt = 0;
    }

    setState(() {
      selectedAmount = amountInt;
    });

    _onAmountChanged(amountInt.toString());
  }

  void _resetCustomAmount() {
    _customAmountController.text = '';
    _formKey.currentState?.validate();
    _customAmountFocus.unfocus();
  }

  Widget buildButtonBar(BuildContext context) {
    buildButtons(double height, double width) => widget.amounts
        .map(
          (amount) => Padding(
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
              fontStyle: ArDriveTypography.body.smallBold().copyWith(
                    fontWeight: FontWeight.w700,
                    color: selectedAmount == amount
                        ? ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeBgSurface
                        : ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgMuted,
                  ),
              text: '${widget.currencyUnit}$amount',
              onPressed: () {
                _onPresetAmountSelected(amount);
                _resetCustomAmount();
              },
            ),
          ),
        )
        .toList();

    return ScreenTypeLayout.builder(
      mobile: (context) => Row(
        mainAxisSize: MainAxisSize.max,
        children: buildButtons(32, 64),
      ),
      desktop: (context) => Row(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: buildButtons(40, 112),
      ),
    );
  }

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
    return ArDriveForm(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            // TODO: Localize
            'Buy Credits',
            style: ArDriveTypography.body.smallBold(),
          ),
          const SizedBox(height: 8),
          Text(
            // TODO: Localize
            'ArDrive Credits will be automatically applied to your wallet, and you can start using them right away.',
            style: ArDriveTypography.body.buttonNormalBold(
              color: ArDriveTheme.of(context).themeData.colors.themeFgSubtle,
            ),
          ),
          // TODO localize
          const SizedBox(height: 32),
          Text(
            'Amount',
            style: ArDriveTypography.body.buttonNormalBold(
              color: ArDriveTheme.of(context).themeData.colors.themeFgSubtle,
            ),
          ),
          const SizedBox(height: 12),
          buildButtonBar(context),
          const SizedBox(height: 16),
          Text(
            'Custom Amount (min \$10 - max \$10,000)',
            style: ArDriveTypography.body.buttonNormalBold(
              color: ArDriveTheme.of(context).themeData.colors.themeFgSubtle,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 114,
                child: ArDriveTheme(
                  key: const ValueKey('turbo_payment_form'),
                  themeData: textTheme,
                  child: ArDriveTextField(
                    focusNode: _customAmountFocus,
                    controller: _customAmountController,
                    showErrorMessage: false,
                    preffix: Text(
                      '\$ ',
                      style: ArDriveTypography.body.buttonLargeBold(
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgDefault,
                      ),
                    ),
                    autovalidateMode: AutovalidateMode.disabled,
                    validator: (s) {
                      setState(() {
                        if (s == null || s.isEmpty) {
                          _customAmountValidationMessage = null;

                          return;
                        }

                        String? errorMessage;

                        final numValue = int.tryParse(s);

                        if (numValue == null ||
                            numValue < 10 ||
                            numValue > 10000) {
                          // TODO: Localize
                          errorMessage =
                              'Please enter an amount between \$10 - \$10,000';
                        }

                        _customAmountValidationMessage = errorMessage;

                        _onCustomAmountSelected(s);
                      });

                      return _customAmountValidationMessage;
                    },
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      TextInputFormatter.withFunction(
                        (oldValue, newValue) {
                          if (int.parse(newValue.text) > 10000) {
                            return oldValue;
                          }
                          return newValue;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              if (_customAmountValidationMessage != null &&
                  _customAmountValidationMessage!.isNotEmpty) ...[
                const SizedBox(width: 8),
                AnimatedFeedbackMessage(
                  text: _customAmountValidationMessage!,
                ),
              ]
            ],
          )
        ],
      ),
    );
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
  balanceContents() => [
        Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appLocalizationsOf(context).arBalance,
              style: ArDriveTypography.body.smallBold(),
            ),
            const SizedBox(height: 4),
            Text(
              '${winstonToAr(widget.balance)} ${appLocalizationsOf(context).creditsTurbo}',
              style: ArDriveTypography.body.buttonXLargeBold(
                color: ArDriveTheme.of(context).themeData.colors.themeFgSubtle,
              ),
            ),
          ],
        ),
        const SizedBox(
          width: 32,
        ),
        Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Estimated Storage',
              style: ArDriveTypography.body.smallBold(),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.estimatedStorage} ${widget.fileSizeUnit}',
              style: ArDriveTypography.body.buttonXLargeBold(
                color: ArDriveTheme.of(context).themeData.colors.themeFgSubtle,
              ),
            ),
          ],
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return ScreenTypeLayout.builder(
      desktop: (context) => Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: balanceContents(),
      ),
      mobile: (context) => Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: balanceContents(),
      ),
    );
  }
}

class PriceEstimateView extends StatelessWidget {
  final int fiatAmount;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 32),
        Text(
          '$fiatCurrency $fiatAmount = ${winstonToAr(estimatedCredits)} ${appLocalizationsOf(context).creditsTurbo} = $estimatedStorage $storageUnit',
          style: ArDriveTypography.body.buttonNormalBold(),
        ),
        const SizedBox(height: 4),
        ArDriveClickArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                // TODO: Localize
                'How are conversions determined?',
                style: ArDriveTypography.body.buttonNormalBold(
                  color:
                      ArDriveTheme.of(context).themeData.colors.themeFgSubtle,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(top: 2.0),
                child: ArDriveIcons.newWindow(
                  color:
                      ArDriveTheme.of(context).themeData.colors.themeFgSubtle,
                  size: 16,
                ),
              )
            ],
          ),
        ),
        const Divider(height: 32),
      ],
    );
  }
}

class CurrencyDropdownMenu extends InputDropdownMenu<CurrencyItem> {
  const CurrencyDropdownMenu({
    super.key,
    required super.items,
    required super.buildSelectedItem,
    // TODO: Localize
    super.label = 'Currency',
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
    // TODO: Localize
    super.label = 'Unit',
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

  const AnimatedFeedbackMessage({Key? key, required this.text})
      : super(key: key);

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
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return ClipRect(
          clipper: _CustomClipper(_animation.value),
          child: child,
        );
      },
      child: FeedbackMessage(
        text: widget.text,
        arrowSide: ArrowSide.right,
        height: 48,
        borderColor: ArDriveTheme.of(context).themeData.colors.themeErrorSubtle,
        backgroundColor:
            ArDriveTheme.of(context).themeData.colors.themeErrorSubtle,
      ),
    );
  }
}

class _CustomClipper extends CustomClipper<Rect> {
  final double progress;

  _CustomClipper(this.progress);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, size.width * progress, size.height);
  }

  @override
  bool shouldReclip(CustomClipper<Rect> oldClipper) {
    return true;
  }
}
