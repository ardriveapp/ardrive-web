import 'dart:async';

import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/blocs/turbo_payment/file_size_units.dart';
import 'package:ardrive/blocs/turbo_payment/turbo_payment_bloc.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/services/turbo/payment_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:responsive_builder/responsive_builder.dart';

class TopUpDialog extends StatefulWidget {
  const TopUpDialog({super.key});

  @override
  State<TopUpDialog> createState() => _TopUpDialogState();
}

class _TopUpDialogState extends State<TopUpDialog> {
  late PaymentBloc paymentBloc;
  late Wallet wallet;

  @override
  initState() {
    wallet = (context.read<ProfileCubit>().state as ProfileLoggedIn).wallet;
    paymentBloc = PaymentBloc(
      paymentService: context.read<PaymentService>(),
      wallet: wallet,
    )..add(LoadInitialData());
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return ArDriveStandardModal(
      width: 575,
      content: BlocBuilder<PaymentBloc, PaymentState>(
        bloc: paymentBloc,
        builder: (context, state) {
          if (state is PaymentLoading) {
            return const SizedBox(
              height: 575,
              child: Center(child: CircularProgressIndicator()),
            );
          } else if (state is PaymentLoaded) {
            return Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    IconButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.close),
                    )
                  ],
                ),
                const SizedBox(height: 16),
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
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          DropdownMenu(
                            label: Text(appLocalizationsOf(context).currency),
                            hintText: appLocalizationsOf(context).currency,
                            initialSelection: paymentBloc.currentCurrency,
                            dropdownMenuEntries: [
                              DropdownMenuEntry(
                                label: paymentBloc.currentCurrency,
                                value: paymentBloc.currentCurrency,
                              ),
                            ],
                          ),
                          const SizedBox(width: 8),
                          DropdownMenu(
                            label: Text(appLocalizationsOf(context).unit),
                            hintText: appLocalizationsOf(context).unit,
                            initialSelection: paymentBloc.currentDataUnit,
                            onSelected: (value) {
                              paymentBloc.add(
                                DataUnitChanged(value as FileSizeUnit),
                              );
                            },
                            dropdownMenuEntries: [
                              ...FileSizeUnit.values.map(
                                (unit) => DropdownMenuEntry(
                                  label: unit.name,
                                  value: unit,
                                  style: ButtonStyle(
                                    foregroundColor:
                                        MaterialStateColor.resolveWith(
                                      (states) => ArDriveTheme.of(context)
                                          .themeData
                                          .colors
                                          .themeFgDefault,
                                    ),
                                  ),
                                ),
                              )
                            ],
                          ),
                        ],
                      ),
                    ),
                    ArDriveButton(
                      text: appLocalizationsOf(context).next,
                      onPressed: () {},
                    ),
                  ],
                )
              ],
            );
          } else if (state is PaymentError) {
            return SizedBox(
              height: 575,
              child: Center(
                child: Text(appLocalizationsOf(context).error),
              ),
            );
          }
          return const SizedBox();
        },
      ),
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

  int selectedAmount = 0;

  @override
  void initState() {
    selectedAmount = widget.preSelectedAmount;
    if (!widget.amounts.contains(selectedAmount)) {
      _customAmountController.text = selectedAmount.toString();
    }

    super.initState();
  }

  DateTime lastChanged = DateTime.now();

  Timer? _timer;

  void _onAmountChanged(String amount) {
    if (amount.isEmpty || int.parse(amount) <= 10) {
      return;
    }

    if (_timer != null && _timer!.isActive) {
      _timer?.cancel();
    }
    _timer = Timer(const Duration(milliseconds: 500), () {
      widget.onAmountSelected(int.parse(amount));
    });
  }

  buildButtonBar(BuildContext context) {
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
                  color: selectedAmount == amount
                      ? ArDriveTheme.of(context).themeData.colors.themeBgSurface
                      : ArDriveTheme.of(context).themeData.colors.themeFgMuted),
              text: '$amount ${widget.currencyUnit}',
              onPressed: () {
                setState(() {
                  selectedAmount = amount;
                  _customAmountController.text = '';
                  widget.onAmountSelected(amount);
                });
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
    return Column(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          appLocalizationsOf(context).buycredits,
          style: ArDriveTypography.body.smallBold(),
        ),
        const SizedBox(height: 8),
        Text(
          // TODO: Localize
          'ArDrive Credits will be automatically applied to your wallet, and you can start using them right away.',
          style: ArDriveTypography.body.buttonNormalBold(
            color: ArDriveTheme.of(context).themeData.colors.themeFgDisabled,
          ),
        ),
        // Text(appLocalizationsOf(context).chooseAnAmount),
        // TODO localize
        const SizedBox(height: 32),
        Text(
          'Amount',
          style: ArDriveTypography.body.buttonNormalBold(
            color: ArDriveTheme.of(context).themeData.colors.themeFgDisabled,
          ),
        ),
        const SizedBox(height: 12),
        buildButtonBar(context),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          // child: Text(appLocalizationsOf(context).orChooseACustomAmount),
          child: Text(
            'Custom Amount (min \$10 - max \$10,000)',
            style: ArDriveTypography.body.buttonNormalBold(
              color: ArDriveTheme.of(context).themeData.colors.themeFgDisabled,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          width: 112,
          height: 40,
          child: TextFormField(
            expands: false,
            controller: _customAmountController,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              //TODO limit to between 10 and 10,000 temporarily
              TextInputFormatter.withFunction(
                (oldValue, newValue) {
                  if (int.parse(newValue.text) > 10000) {
                    return oldValue;
                  }
                  return newValue;
                },
              ),
            ],
            onChanged: (value) {
              setState(() {
                selectedAmount = int.tryParse(value) ?? 0;
              });
              _onAmountChanged(value);
            },
          ),
        )
      ],
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
              appLocalizationsOf(context).balanceAR,
              style: ArDriveTypography.body.smallBold(),
            ),
            const SizedBox(height: 4),
            Text(
              '${winstonToAr(widget.balance)} ${appLocalizationsOf(context).creditsTurbo}',
              style: ArDriveTypography.body.buttonXLargeBold(
                color:
                    ArDriveTheme.of(context).themeData.colors.themeFgDisabled,
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
              appLocalizationsOf(context).estimatedStorage,
              style: ArDriveTypography.body.smallBold(),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.estimatedStorage} ${widget.fileSizeUnit}',
              style: ArDriveTypography.body.buttonXLargeBold(
                color:
                    ArDriveTheme.of(context).themeData.colors.themeFgDisabled,
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
        const SizedBox(height: 16),
        ArDriveClickArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                appLocalizationsOf(context).howAreConversionsDetermined,
                style: ArDriveTypography.body.buttonNormalBold(
                  color:
                      ArDriveTheme.of(context).themeData.colors.themeFgDisabled,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(top: 2.0),
                child: ArDriveIcons.newWindow(
                  color:
                      ArDriveTheme.of(context).themeData.colors.themeFgDisabled,
                  size: 12,
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
